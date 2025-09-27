jl_encrypt :: (plain: []u8, key: [32]u8, allocator:=context.allocator) -> ([]u8, bool) {
	push_allocator(allocator);
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
	push_allocator(allocator);
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


#import,dir "modules/openssl";

#scope_file;
IV : [16]u8= cast([16]u8)"vwvwvwvwvwvwvwvw";

encrypt_test :: () {
	key:= sha256("Whatever");
	iv : [16]u8= .[2,4,6,8,2,4,6,8,2,4,6,8,2,4,6,8];
	args := get_command_line_arguments();
	plain := ifx args.count > 1 then args[1] else "And you don't seem to understand.";

	cipher : []u8;
	{// Encypt the file.
		ctx := EVP_CIPHER_CTX_new(); defer EVP_CIPHER_CTX_free(ctx);
		EVP_EncryptInit_ex(ctx, EVP_aes_256_cbc(), null, key.data, iv.data);
		buffer := NewArray(plain.count * 2, u8, false); defer array_free(buffer);
		total : s32;
		size : s32;
		EVP_EncryptUpdate(ctx, buffer.data, *size, plain.data, xx plain.count); // ctx: *EVP_CIPHER_CTX, out: *u8, outlen: *cint, in: *u8, inlen: cint
		total += size;
		if EVP_EncryptFinal_ex(ctx, buffer.data+total, *size) == 0 { // ctx: *EVP_CIPHER_CTX, out: *u8, outlen: *cint
			print("Encryption failed.\n");
		} else {
			total += size;
			result := slice(xx buffer, 0, total);
			cipher = xx result;
			write_entire_file("secret", result);
			print("encrypted: %\n", result);
		}
	}
	data, ok := read_entire_file("secret");
	if ok {// Decrypt what's in file `secret`.
		ctx := EVP_CIPHER_CTX_new(); defer EVP_CIPHER_CTX_free(ctx);
		EVP_DecryptInit_ex(ctx, EVP_aes_256_cbc(), null, key.data, iv.data);
		buffer := NewArray(plain.count * 4, u8, false); defer array_free(buffer);
		total : s32;
		size : s32;

		EVP_DecryptUpdate(ctx, buffer.data, *size, data.data, xx data.count);
		total += size;
		if EVP_DecryptFinal_ex(ctx, buffer.data+total, *size) == 0 {
			total += size;
			result := slice(xx buffer, 0, total);
			print("Decryption failed. : %\n", result);
		} else {
			total += size;
			result := slice(xx buffer, 0, total);
			print("What's in the secret: %\n", result);
		}
	}
}

