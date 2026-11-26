#import,dir "modules/openssl";

// Encryption of a jl file.
//
// v2 (current format): AES-256-GCM. The 60-byte header is authenticated as
//  associated data, so salt, nonce and the KDF parameters cannot be altered.
//  The file key is `scrypt(SHA256(password), salt)`, with a random per-file
//  salt and a random nonce for every write.
//
// v1 (legacy format): AES-256-CBC with `key = SHA256(password)` and a constant
//  IV. Read-only; the next save rewrites the file as v2.
//
// Both formats derive from `password_sha256`, the 32 bytes which are also what
// `credential.jai` stores. That is what makes the silent upgrade possible: an
// upgraded file never needs the plaintext password again.

JL_ENC_V1_MAGIC :[16]u8: xx "VMWVWWWVWWVMVWMM";
JL_ENC_V2_MAGIC :[16]u8: xx "VMWVWWWVWWVMVWM2";

Enc_Version :: enum u8 {
	invalid;
	v1;
	v2;
}

Enc_Header :: struct {
	magic      : [16]u8;
	version    : u8;
	cipher     : u8;
	kdf        : u8;
	reserved   : u8;
	kdf_param0 : u32; // scrypt: log2(N)
	kdf_param1 : u32; // scrypt: r
	kdf_param2 : u32; // scrypt: p
	salt       : [16]u8;
	nonce      : [12]u8;
}

ENC_SALT_SIZE  :: 16;
ENC_NONCE_SIZE :: 12;
ENC_TAG_SIZE   :: 16;

ENC_CIPHER_AES256GCM :: 1;
ENC_KDF_SCRYPT       :: 1;

// 2^15 * r=8 * p=1 costs about 33 MB of memory and ~65 ms per derivation on a
// modern desktop CPU.
ENC_SCRYPT_LOG2N  :: 15;
ENC_SCRYPT_R      :: 8;
ENC_SCRYPT_P      :: 1;
ENC_SCRYPT_MAXMEM :: 64 * 1024 * 1024;

is_data_jl_encrypted :: inline (data: []u8) -> bool {
	if data.count < 16 return false;
	return memcmp(data.data, JL_ENC_V1_MAGIC.data, 16) == 0
	    || memcmp(data.data, JL_ENC_V2_MAGIC.data, 16) == 0;
}

jlfile_encryption_version :: (data: []u8) -> Enc_Version {
	if data.count < 16 return .invalid;
	if memcmp(data.data, JL_ENC_V2_MAGIC.data, 16) == 0 return .v2;
	if memcmp(data.data, JL_ENC_V1_MAGIC.data, 16) == 0 return .v1;
	return .invalid;
}

// Encrypts `plain` into a complete file body (header + ciphertext + tag).
jl_encrypt :: (plain: []u8, password_sha256: [32]u8, allocator:=context.allocator) -> ([]u8, bool) {
	push_allocator(allocator);

	HEADER_SIZE :: size_of(Enc_Header);

	header : Enc_Header;
	memcpy(header.magic.data, JL_ENC_V2_MAGIC.data, 16);
	header.version    = xx Enc_Version.v2;
	header.cipher     = ENC_CIPHER_AES256GCM;
	header.kdf        = ENC_KDF_SCRYPT;
	header.kdf_param0 = ENC_SCRYPT_LOG2N;
	header.kdf_param1 = ENC_SCRYPT_R;
	header.kdf_param2 = ENC_SCRYPT_P;
	if RAND_bytes(header.salt.data, ENC_SALT_SIZE) != 1 return .{}, false;
	if RAND_bytes(header.nonce.data, ENC_NONCE_SIZE) != 1 return .{}, false;

	key : [32]u8;
	if !derive_file_key(password_sha256, header, *key) return .{}, false;

	buffer := NewArray(HEADER_SIZE + plain.count + ENC_TAG_SIZE, u8, false);
	memcpy(buffer.data, *header, HEADER_SIZE);

	ctx := EVP_CIPHER_CTX_new(); defer EVP_CIPHER_CTX_free(ctx);
	EVP_EncryptInit_ex(ctx, EVP_aes_256_gcm(), null, null, null);
	EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, ENC_NONCE_SIZE, null);
	EVP_EncryptInit_ex(ctx, null, null, key.data, header.nonce.data);

	size : s32;
	EVP_EncryptUpdate(ctx, null, *size, buffer.data, HEADER_SIZE); // header as AAD
	total := HEADER_SIZE;
	EVP_EncryptUpdate(ctx, buffer.data+total, *size, plain.data, xx plain.count);
	total += size;
	if EVP_EncryptFinal_ex(ctx, buffer.data+total, *size) == 0 {
		array_free(buffer);
		return .{}, false;
	}
	total += size;
	if EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, ENC_TAG_SIZE, buffer.data+total) != 1 {
		array_free(buffer);
		return .{}, false;
	}
	total += ENC_TAG_SIZE;

	return array_view(buffer, 0, total), true;
}

// Decrypts a complete file body, whatever version it is.
jl_decrypt :: (body: []u8, password_sha256: [32]u8, allocator:=context.allocator) -> ([]u8, bool, Enc_Version) {
	push_allocator(allocator);

	version := jlfile_encryption_version(body);
	if version == .v2 {
		plain, ok := jl_decrypt_v2(body, password_sha256, allocator);
		return plain, ok, .v2;
	}
	if version == .v1 {
		plain, ok := jl_decrypt_v1(body, password_sha256, allocator);
		return plain, ok, .v1;
	}
	return .{}, false, .invalid;
}

sha256_raw_to_hex :: (raw: [32]u8) -> [64]u8 {
	digits :: "0123456789abcdef";
	hex :[64]u8= ---;
	for i: 0..31 {
		hex[i * 2]     = digits[(raw[i] >> 4) & 0xF];
		hex[i * 2 + 1] = digits[raw[i] & 0xF];
	}
	return hex;
}

sha256_hex_to_raw :: (hex: [64]u8) -> [32]u8, bool {
	hexval :: (c: u8) -> int {
		if (#char "0" <= c && c <= #char "9") return c - #char "0";
		if (#char "a" <= c && c <= #char "f") return c - #char "a" + 10;
		if (#char "A" <= c && c <= #char "F") return c - #char "A" + 10;
		return -1;
	};
	raw :[32]u8= --- ;

	for i: 0..31 {
		hi := hexval(hex[i * 2]);
		lo := hexval(hex[i * 2 + 1]);
		if (hi < 0 || lo < 0) return raw, false;
		raw[i] = (cast(u8)hi << 4) | cast(u8)lo;
	}
	return raw, true;
}

#scope_file;

// The IV of the legacy v1 format. Only used to read old files.
IV : [16]u8= cast([16]u8)"vwvwvwvwvwvwvwvw";

derive_file_key :: (password_sha256: [32]u8, header: Enc_Header, outkey: *[32]u8) -> bool {
	if header.kdf != ENC_KDF_SCRYPT return false;
	// Bounds check so that a crafted header cannot make us allocate gigabytes.
	if header.kdf_param0 < 10 || header.kdf_param0 > 20 return false;
	if header.kdf_param1 < 1  || header.kdf_param1 > 16 return false;
	if header.kdf_param2 < 1  || header.kdf_param2 > 4  return false;

	n := cast(u64)1 << xx header.kdf_param0;
	rc := EVP_PBE_scrypt(password_sha256.data, 32,
	                     header.salt.data, ENC_SALT_SIZE,
	                     n, xx header.kdf_param1, xx header.kdf_param2,
	                     ENC_SCRYPT_MAXMEM, outkey.data, 32);
	return rc == 1;
}

jl_decrypt_v2 :: (body: []u8, password_sha256: [32]u8, allocator: Allocator) -> ([]u8, bool) {
	push_allocator(allocator);

	HEADER_SIZE :: size_of(Enc_Header);
	if body.count < HEADER_SIZE + ENC_TAG_SIZE return .{}, false;

	header := cast(*Enc_Header)body.data;
	if header.version != xx Enc_Version.v2 return .{}, false;
	if header.cipher  != ENC_CIPHER_AES256GCM return .{}, false;

	key : [32]u8;
	if !derive_file_key(password_sha256, header.*, *key) return .{}, false;

	cipher_len := body.count - HEADER_SIZE - ENC_TAG_SIZE;
	cipher     := array_view(body, HEADER_SIZE, cipher_len);
	tag        := array_view(body, body.count-ENC_TAG_SIZE, ENC_TAG_SIZE);

	buffer := NewArray(cipher_len + 32, u8, false);

	ctx := EVP_CIPHER_CTX_new(); defer EVP_CIPHER_CTX_free(ctx);
	EVP_DecryptInit_ex(ctx, EVP_aes_256_gcm(), null, null, null);
	EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, ENC_NONCE_SIZE, null);
	EVP_DecryptInit_ex(ctx, null, null, key.data, header.nonce.data);

	size : s32;
	EVP_DecryptUpdate(ctx, null, *size, body.data, HEADER_SIZE); // header as AAD
	total := 0;
	EVP_DecryptUpdate(ctx, buffer.data, *size, cipher.data, xx cipher.count);
	total += size;
	if EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, ENC_TAG_SIZE, tag.data) != 1 {
		array_free(buffer);
		return .{}, false;
	}
	if EVP_DecryptFinal_ex(ctx, buffer.data+total, *size) <= 0 {
		array_free(buffer); // authentication failed: wrong key or tampered file
		return .{}, false;
	}
	total += size;

	return array_view(buffer, 0, total), true;
}

jl_decrypt_v1 :: (body: []u8, password_sha256: [32]u8, allocator: Allocator) -> ([]u8, bool) {
	push_allocator(allocator);

	if body.count <= 16 return .{}, false;
	cipher := array_view(body, 16, body.count-16);
	if cipher.count % 16 != 0 return .{}, false;

	buffer := NewArray(cipher.count + 32, u8, false);

	ctx := EVP_CIPHER_CTX_new(); defer EVP_CIPHER_CTX_free(ctx);
	EVP_DecryptInit_ex(ctx, EVP_aes_256_cbc(), null, password_sha256.data, IV.data);

	size : s32;
	total := 0;
	EVP_DecryptUpdate(ctx, buffer.data, *size, cipher.data, xx cipher.count);
	total += size;
	if EVP_DecryptFinal_ex(ctx, buffer.data+total, *size) == 0 {
		array_free(buffer);
		return .{}, false;
	}
	total += size;

	return array_view(buffer, 0, total), true;
}

