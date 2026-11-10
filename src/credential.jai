// Stores the key used to encrypt a jl file.
// On Windows this uses the Credential Manager; other platforms fall back to
// the `default.key` file used by older versions of jl.

#if OS == .WINDOWS {
	save_stored_key :: (target: string, key: [32]u8) -> bool {
		push_allocator(temp);

		wide_target, target_ok, _ := utf8_to_wide(target);
		if !target_ok return false;

		wide_user, user_ok, _ := utf8_to_wide("jl");
		if !user_ok return false;

		cred := CREDENTIALW.{
			Type               = CRED_TYPE_GENERIC,
			TargetName         = wide_target,
			CredentialBlobSize = 32,
			CredentialBlob     = key.data,
			Persist            = CRED_PERSIST_LOCAL_MACHINE,
			UserName           = wide_user,
		};
		if CredWriteW(*cred, 0) == 0 return false;

		delete_key_file();
		return true;
	}

	load_stored_key :: (target: string, outkey: *[32]u8) -> (ok: bool, credential_found: bool) {
		push_allocator(temp);

		wide_target, target_ok, _ := utf8_to_wide(target);
		if target_ok {
			cred : *CREDENTIALW;
			if CredReadW(wide_target, CRED_TYPE_GENERIC, 0, *cred) != 0 {
				defer CredFree(cred);
				if cred.CredentialBlobSize == 32 {
					memcpy(outkey.data, cred.CredentialBlob, 32);
					return true, true;
				}
				return false, true;
			}
		}

		return load_key_file(outkey), false;
	}

	delete_stored_key :: (target: string) -> bool {
		push_allocator(temp);

		deleted := false;
		wide_target, target_ok, _ := utf8_to_wide(target);
		if target_ok && CredDeleteW(wide_target, CRED_TYPE_GENERIC, 0) != 0 {
			deleted = true;
		}

		if delete_key_file() deleted = true;
		return deleted;
	}
} else {
	save_stored_key :: (target: string, key: [32]u8) -> bool {
		return save_key_file(key);
	}

	load_stored_key :: (target: string, outkey: *[32]u8) -> (ok: bool, credential_found: bool) {
		return load_key_file(outkey), false;
	}

	delete_stored_key :: (target: string) -> bool {
		return delete_key_file();
	}
}

#import "Basic";
#import "Windows_Utf8";

#scope_file;

save_key_file :: (key: [32]u8) -> bool {
	keypath := get_jl_filepath("default.key", temp);
	return write_entire_file(keypath, cast(string)sha256_raw_to_hex(key));
}

load_key_file :: (outkey: *[32]u8) -> bool {
	keypath := get_jl_filepath("default.key", temp);
	hexkey, ok := read_entire_file(keypath, log_errors=false);
	if !ok return false;
	defer free(hexkey);

	if hexkey.count != 64 return false;
	rawkey, convert_ok := sha256_hex_to_raw(cast([64]u8)hexkey.data);
	if !convert_ok return false;

	outkey.* = rawkey;
	return true;
}

delete_key_file :: () -> bool {
	keypath := get_jl_filepath("default.key", temp);
	return file_delete(keypath);
}

#if OS == .WINDOWS {
	CRED_TYPE_GENERIC          :: 1;
	CRED_PERSIST_LOCAL_MACHINE :: 2;

	CREDENTIALW :: struct {
		Flags              : u32;
		Type               : u32;
		TargetName         : *u16;
		Comment            : *u16;
		LastWritten        : u64;
		CredentialBlobSize : u32;
		CredentialBlob     : *u8;
		Persist            : u32;
		AttributeCount     : u32;
		Attributes         : *void;
		TargetAlias        : *u16;
		UserName           : *u16;
	}

	advapi32 :: #library,system "Advapi32";

	CredWriteW  :: (Credential: *CREDENTIALW, Flags: u32) -> s32 #foreign advapi32;
	CredReadW   :: (TargetName: *u16, Type: u32, Flags: u32, Credential: **CREDENTIALW) -> s32 #foreign advapi32;
	CredDeleteW :: (TargetName: *u16, Type: u32, Flags: u32) -> s32 #foreign advapi32;
	CredFree    :: (Buffer: *void) #foreign advapi32;
}
