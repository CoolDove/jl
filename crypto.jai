jl_encrypt :: (plain: []u8, key: [32]u8, allocator:=context.allocator) -> ([]u8, bool) {
	ctx := EVP_CIPHER_CTX_new(); defer EVP_CIPHER_CTX_free(ctx);
	EVP_EncryptInit_ex(ctx, EVP_aes_256_cbc(), null, key.data, IV.data);

	buffer := NewArray(plain.count + 32, u8, false);
	total : s32;
	size : s32;
	EVP_EncryptUpdate(ctx, buffer.data, *size, plain.data, xx plain.count);
	total += size;
	if EVP_EncryptFinal_ex(ctx, buffer.data+total, *size) == 0 {
		array_free(buffer);
		return .{}, false;
	} else {
		total += size;
		result := array_view(buffer, 0, total);
		return result, true;
	}
}

jl_decrypt :: (cipher: []u8, key: [32]u8, allocator:=context.allocator) -> ([]u8, bool) {
	ctx := EVP_CIPHER_CTX_new(); defer EVP_CIPHER_CTX_free(ctx);
	EVP_DecryptInit_ex(ctx, EVP_aes_256_cbc(), null, key.data, IV.data);
	buffer := NewArray(cipher.count * 4, u8, false);
	total : s32;
	size : s32;

	EVP_DecryptUpdate(ctx, buffer.data, *size, cipher.data, xx cipher.count);
	total += size;
	if EVP_DecryptFinal_ex(ctx, buffer.data+total, *size) == 0 {
		array_free(buffer);
		return .{}, false;
	} else {
		total += size;
		result := array_view(buffer, 0, total);
		return result, true;
	}
}

#import,dir "modules/openssl";

#scope_file;
IV : [16]u8= cast([16]u8)"vwvwvwvwvwvwvwvw";
