#module_parameters(OPENSSL_SHARED := false);

#if OS == .WINDOWS {
	#if OPENSSL_SHARED {
		libssl    :: #library "includes/windows/libssl";
		libcrypto :: #library "includes/windows/libcrypto";
	} else {
		libssl    :: #library,no_dll "includes/windows/libssl_static";
		libcrypto :: #library,no_dll "includes/windows/libcrypto_static";
		ws2_32    :: #library,system,link_always "ws2_32";
		gdi32     :: #library,system,link_always "gdi32";
		advapi32  :: #library,system,link_always "advapi32";
		crypt32   :: #library,system,link_always "crypt32";
		user32    :: #library,system,link_always "user32";
	}
} else {
	libopenssl :: #library,system "ssl";
	libcrypto  :: #library,system "crypto";
}

Version :: enum u32 {
	pre_release :: 0 | 4;
	patch       :: 0 | 16;
	minor       :: 0 | 8;
	major       :: 0 | 4;
}
VERSION: Version;

cint   :: #type s32;
cuint  :: #type u32;
clong  :: #type s64;
culong :: #type u64;
FILE   :: void;

SSL_METHOD :: struct {};
SSL_CTX    :: struct {};
SSL        :: struct {};

SSL_CTRL_SET_TLSEXT_HOSTNAME :: 55;

TLSEXT_NAMETYPE_host_name :: 0;

TLS_client_method :: () -> *SSL_METHOD #foreign libssl;
SSL_CTX_new :: (method: *SSL_METHOD) -> *SSL_CTX #foreign libssl;
SSL_new :: (ctx: *SSL_CTX) -> *SSL #foreign libssl;
SSL_set_fd :: (ssl: *SSL, fd: cint) -> cint #foreign libssl;
SSL_connect :: (ssl: *SSL) -> cint #foreign libssl;
SSL_get_error :: (ssl: *SSL, ret: cint) -> cint #foreign libssl;
SSL_read :: (ssl: *SSL, buf: *u8, num: cint) -> cint #foreign libssl;
SSL_write :: (ssl: *SSL, buf: *u8, num: cint) -> cint #foreign libssl;
SSL_free :: (ssl: *SSL) #foreign libssl;
SSL_CTX_free :: (ctx: *SSL_CTX) #foreign libssl;
ERR_print_errors_fp :: (fp: *FILE) #foreign libssl;
SSL_ctrl :: (ssl: *SSL, cmd: cint, larg: clong, parg: *void) -> clong #foreign libssl;
OpenSSL_version_num :: () -> culong #foreign libssl;

SSL_set_tlsext_host_name :: (ssl: *SSL, name: *u8) -> cint {
	return cast(cint)SSL_ctrl(ssl, SSL_CTRL_SET_TLSEXT_HOSTNAME, TLSEXT_NAMETYPE_host_name, name);
}

ERR_printe_stderr :: () {
	ERR_print_errors_fp(2);
}

// ------


EVP_CIPHER       :: void;
EVP_CIPHER_CTX   :: void;
EVP_MD           :: void;
EVP_MD_CTX       :: void;
ENGINE           :: void;

EVP_CIPHER_CTX_new     :: () -> *EVP_CIPHER_CTX #foreign libcrypto;
EVP_CIPHER_CTX_free    :: (ctx: *EVP_CIPHER_CTX) #foreign libcrypto;

EVP_CIPHER_CTX_set_key_length :: (ctx: *EVP_CIPHER_CTX, keylen: cint) -> cint #foreign libcrypto;
EVP_CIPHER_CTX_set_padding    :: (ctx: *EVP_CIPHER_CTX, pad: cint) -> cint #foreign libcrypto;

EVP_aes_256_cbc        :: () -> *EVP_CIPHER #foreign libcrypto;

EVP_EncryptInit_ex     :: (ctx: *EVP_CIPHER_CTX, cipher: *EVP_CIPHER, engine: *ENGINE, key: *u8, iv: *u8) -> cint #foreign libcrypto;
EVP_EncryptUpdate      :: (ctx: *EVP_CIPHER_CTX, out: *u8, outlen: *cint, in: *u8, inlen: cint) -> cint #foreign libcrypto;
EVP_EncryptFinal_ex    :: (ctx: *EVP_CIPHER_CTX, out: *u8, outlen: *cint) -> cint #foreign libcrypto;

EVP_DecryptInit_ex     :: (ctx: *EVP_CIPHER_CTX, cipher: *EVP_CIPHER, engine: *ENGINE, key: *u8, iv: *u8) -> cint #foreign libcrypto;
EVP_DecryptUpdate      :: (ctx: *EVP_CIPHER_CTX, out: *u8, outlen: *cint, in: *u8, inlen: cint) -> cint #foreign libcrypto;
EVP_DecryptFinal_ex    :: (ctx: *EVP_CIPHER_CTX, out: *u8, outlen: *cint) -> cint #foreign libcrypto;

EVP_DigestInit_ex      :: (ctx: *EVP_MD_CTX, type: *EVP_MD, impl: *ENGINE) -> cint #foreign libcrypto;
EVP_DigestUpdate       :: (ctx: *EVP_MD_CTX, data: *u8, count: culong) -> cint #foreign libcrypto;
EVP_DigestFinal_ex     :: (ctx: *EVP_MD_CTX, md: *u8, size: *cuint) -> cint #foreign libcrypto;

EVP_MD_CTX_new         :: () -> *EVP_MD_CTX #foreign libcrypto;
EVP_MD_CTX_free        :: (ctx: *EVP_MD_CTX) #foreign libcrypto;

EVP_sha256             :: () -> *EVP_MD #foreign libcrypto;

SHA256                 :: (d: *u8, n: culong, md: *u8) -> *u8 #foreign libcrypto;

PKCS5_PBKDF2_HMAC :: (pass: *u8, passlen: cint, salt: *u8, saltlen: cint, iter: cint, digest: *EVP_MD, keylen: cint, out: *u8) -> int #foreign libcrypto;

// Can use this to generate IV.
RAND_bytes             :: (buf: *u8, num: cint) -> cint #foreign libcrypto;
