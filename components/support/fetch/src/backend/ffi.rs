/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

use crate::settings::GLOBAL_SETTINGS;
use crate::{msg_types, Error};
use ffi_support::ByteBuffer;

ffi_support::implement_into_ffi_by_protobuf!(msg_types::Request);

impl From<crate::Request> for msg_types::Request {
    fn from(request: crate::Request) -> Self {
        msg_types::Request {
            url: request.url.into_string(),
            body: request.body,
            // Real weird that this needs to be specified as an i32, but
            // it certainly makes it convenient for us...
            method: request.method as i32,
            headers: request.headers.into(),
            follow_redirects: GLOBAL_SETTINGS.follow_redirects,
            include_cookies: GLOBAL_SETTINGS.include_cookies,
            use_caches: GLOBAL_SETTINGS.use_caches,
            connect_timeout_secs: GLOBAL_SETTINGS
                .connect_timeout
                .map_or(0, |d| d.as_secs() as i32),
            read_timeout_secs: GLOBAL_SETTINGS
                .read_timeout
                .map_or(0, |d| d.as_secs() as i32),
        }
    }
}

macro_rules! backend_error {
    ($($args:tt)*) => {{
        let msg = format!($($args)*);
        log::error!("{}", msg);
        Error::BackendError(msg)
    }};
}

pub fn send(request: crate::Request) -> Result<crate::Response, Error> {
    use ffi_support::IntoFfi;
    use prost::Message;

    let method = request.method;
    let fetch = callback_holder::get_callback().ok_or_else(|| Error::BackendNotInitialized)?;
    let proto_req: msg_types::Request = request.into();
    let buf = proto_req.into_ffi_value();
    let response = unsafe { fetch(buf) };
    // This way we'll Drop it if we panic, unlike if we just got a slice into
    // it. Besides, we already own it.
    let response_bytes = response.into_vec();

    let response: msg_types::Response = match Message::decode(&response_bytes) {
        Ok(v) => v,
        Err(e) => {
            panic!(
                "Failed to parse protobuf returned from fetch callback! {}",
                e
            );
        }
    };

    if let Some(exn) = response.exception {
        let exn_name = exn
            .name
            .as_ref()
            .map(|s| s.as_str())
            .unwrap_or("<unknown exception>");
        let exn_msg = exn
            .msg
            .as_ref()
            .map(|s| s.as_str())
            .unwrap_or("<no message provided>");
        log::error!(
            // Well, we caught *something* java wanted to tell us about, anyway.
            "Caught network error (presumably). Type: {}, message: {:?}",
            exn_name,
            exn_msg
        );
        return Err(Error::NetworkError(format!("{}: {:?}", exn_name, exn_msg)));
    }
    let status = response
        .status
        .ok_or_else(|| backend_error!("Missing HTTP status"))?;

    if status < 0 || status > i32::from(u16::max_value()) {
        return Err(backend_error!("Illegal HTTP status: {}", status));
    }

    let mut headers = crate::Headers::with_capacity(response.headers.len());
    for (name, val) in response.headers {
        let hname = crate::HeaderName::new(name)
            .map_err(|e| backend_error!("Response has illegal header name: {}", e))?;
        headers.insert(hname, val);
    }

    let url = url::Url::parse(
        &response
            .url
            .ok_or_else(|| backend_error!("Response has no URL"))?,
    )
    .map_err(|e| backend_error!("Response has illegal URL: {}", e))?;

    Ok(crate::Response {
        url,
        request_method: method,
        body_text: response.body.unwrap_or_default(),
        status: status as u16,
        headers,
    })
}

/// Type of the callback we need callers on the other side of the FFI to
/// provide.
///
/// Takes and returns a ffi_support::ByteBuffer. (TODO: it would be nice if we could
/// make this take/return pointers, so that we could use JNA direct mapping. Maybe
/// we need some kind of ThinBuffer?)
///
/// This is a bit weird, since it requires us to allow code on the other side of
/// the FFI to allocate a ByteBuffer from us, but it works.
///
/// The code on the other side of the FFI is responsible for freeing the ByteBuffer
/// it's passed using `support_fetch_destroy_bytebuffer`.
type FetchCallback = unsafe extern "C" fn(ByteBuffer) -> ByteBuffer;

/// Module that manages get/set of the global fetch callback pointer.
mod callback_holder {
    use super::FetchCallback;
    use std::sync::atomic::{AtomicUsize, Ordering};

    /// Note: We only assign to this once.
    static CALLBACK_PTR: AtomicUsize = AtomicUsize::new(0);

    /// Get the function pointer to the FetchCallback. Panics if the callback
    /// has not yet been initialized.
    pub(super) fn get_callback() -> Option<FetchCallback> {
        let ptr = CALLBACK_PTR.load(Ordering::SeqCst) as *const FetchCallback;
        if ptr.is_null() {
            None
        } else {
            Some(unsafe { *ptr })
        }
    }

    /// Set the function pointer to the FetchCallback. Panics if the callback
    /// has already been initialized.
    pub(super) unsafe fn set_callback(h: *const FetchCallback) {
        let old_ptr = CALLBACK_PTR.compare_and_swap(0, h as usize, Ordering::SeqCst);
        if old_ptr != 0 {
            // This is an internal bug, the other side of the FFI should ensure it sets this only once.
            panic!("Bug: Initialized CALLBACK_PTR multiple times");
        }
    }
}

/// Return a ByteBuffer of the requested size. This is used to store the
/// response from the callback.
#[no_mangle]
pub extern "C" fn support_fetch_alloc_bytebuffer(
    sz: i64,
    error: &mut ffi_support::ExternError,
) -> ByteBuffer {
    ffi_support::call_with_output(error, || {
        assert!(
            sz > 0,
            "Negative size passed to support_fetch_alloc_bytebuffer: {}",
            sz
        );
        ByteBuffer::new_with_size(sz as usize)
    })
}

#[no_mangle]
pub unsafe extern "C" fn support_fetch_initialize(
    callback: *const FetchCallback,
    error: &mut ffi_support::ExternError,
) {
    ffi_support::call_with_output(error, || {
        callback_holder::set_callback(callback);
    })
}

ffi_support::define_bytebuffer_destructor!(support_fetch_destroy_bytebuffer);
