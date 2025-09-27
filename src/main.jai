#load "args_reader.jai";
#load "utils.jai";
#load "config.jai";
#load "console.jai";
#load "crypto.jai";
#load "time.jai";
#load "jl.jai";

process_edit : Process;

jlfile : JlFile;

matched_records : [..]*JlRecord; // No need to free~

info : struct {
	all     : int;
	loaded  : int;
	editted : int;
}

runinfo :struct {
	target_file  : string;

	filter_specified    : bool;
	operation_specified : bool;
	only_today          : bool;

	// password : string;
	password_sha256 : [32]u8;
	file_is_encrypted : bool;

	create_mode  : bool;

	operation    : OperationMode;
	OperationMode :: enum u8 {
		Edit;
		ListTags;
		Print;
	}
}

main :: () {
	#if false { // test read input
		print("Input: ");
		read := read_stdin(true);
		print("What i read: [%]\n", read);
		exit(0);
	}
	#if false {// test encryption
		secret : string;
		assert(test_encryption(*secret));
		print("secret:\n%\n", secret);
	}

	init_console();

	args := get_command_line_arguments();

	jlfolder := get_jl_directory();
	make_directory_if_it_does_not_exist(jlfolder);

	// @Temporary: We will have a config file.
	runinfo.target_file = to_string(getenv("JLDEFAULTFILE"));
	if runinfo.target_file.data == null {
		runinfo.target_file = get_jl_filepath("default.jl"); // No free!
	}
	print("Load jlfile from '%' .\n", runinfo.target_file);

	runinfo.create_mode = args.count == 1;

	// ** filtering
	tags :[..]string; defer free(tags.data);
	// NOTE: If the filter is not specified, we load all the records.
	// Running `jl` with no argument, will lead to create mode.
	for args {
		if it_index == 0 continue;
		if it[0] == #char "@" {
			array_add(*tags, it);
			runinfo.filter_specified = true;
		} else if it == "-today" || it == "-t" {// @Temporary: We will have a better time filtering.
			runinfo.only_today = true;
			runinfo.filter_specified = true;
		} else if it == "--e" || it == "--edit" {
			runinfo.operation = .Edit;
			runinfo.operation_specified = true;
		} else if it == "--p" || it == "--print" {
			runinfo.operation = .Print;
			runinfo.operation_specified = true;
		} else if it == "--t" || it == "--tags" {
			runinfo.operation = .ListTags;
			runinfo.operation_specified = true;
		} else if it == "--help" || it == "-help" || it == "--h" || it == "-h" {
			print(HELP_STRING);
			exit(0);
		} else if begins_with(it, "--decrypt") {
			operation_decrypt();// pre pass
			exit(0);
		} else if begins_with(it, "--encrypt-save-key") {
			operation_encrypt(true);// pre pass
			exit(0);
		} else if begins_with(it, "--encrypt") {
			operation_encrypt(false);// pre pass
			exit(0);
		} else {
			print("Unknown arguments.\n");
			exit(0);
		}
	}

	// ** load file
	file_content, file_read_good := read_entire_file(runinfo.target_file, log_errors=false);
	defer if file_read_good free(file_content);

	if !file_read_good {
		if confirm_yn(tprint("File \e[31m%\e[39m doesn't exist, create?", runinfo.target_file)) {
			path, _, _, _ := path_decomp(runinfo.target_file);
			make_directory_if_it_does_not_exist(path, true);
			runinfo.create_mode = true;
			write_entire_file(runinfo.target_file, "");
		} else {
			log_error("Can't read file '%'.", runinfo.target_file);
			exit(1);
		}
	}

	content : string;
	if is_data_jl_encrypted(xx file_content) { // load encrypted file
		using runinfo;
		file_is_encrypted = true;

		if !try_get_stored_key(*password_sha256) {
			print("Password:");
			password_sha256 = sha256(read_pswd(allocator=temp));
		}
		cipher := get_encrypted_jlfile_cipher(xx file_content); // slice(file_content, JLMAGIC.count, file_content.count-JLMAGIC.count);
		data, decrypt_ok := jl_decrypt(xx cipher, password_sha256);
		if !decrypt_ok {
			print("Wrong password.");
			exit(0);
		} else {
			content = xx data;
		}
	} else {
		content = file_content;
	}

	jlfile = jlfile_parse(content); defer jlfile_release(*jlfile);
	info.all = jlfile.records.count;

	now := to_calendar(current_time_consensus(), .LOCAL);

	if runinfo.filter_specified {
		for * jlfile.records {
			_, title_line, _ := split_from_left(it.content, #char "\n");
			match := true;
			if runinfo.only_today && !is_same_day(it.time, now) {
				match = false;
			}
			if match for tag: tags {
				if !contains(title_line, tag) {
					match = false;
					break;
				}
			}
			if match {
				array_add(*matched_records, it);
			} else {
				it.exclude = true;
			}
		}
	} else {
		for * jlfile.records array_add(*matched_records, it);
	}

	bubble_sort(array_view(matched_records, 0), (a: *JlRecord, b: *JlRecord) -> int {
		return ifx a.apollo_time > b.apollo_time then -1 else 1;
	});

	if #complete runinfo.operation == {
		case .Edit;
			operation_edit();
		case .Print;
			operation_print();
		case .ListTags;
			operation_list_tags();
	}
}

operation_edit :: () {
	// ** get editor
	#if OS == .WINDOWS {
		default_editor :*u8: "notepade.exe";
	} else {
		default_editor :*u8: null;
	}

	editor :*u8= getenv("JLEDITOR");
	if editor == null editor = getenv("EDITOR");
	if editor == null editor = default_editor;
	assert(editor!=null, "No editor available.");
	editor_str := to_string(editor);

	// ** run the editor
	edit_file := get_jl_filepath("~edit.jl"); defer free(edit_file.data);
	{// ** create the edit file
		edfile := file_open(edit_file, for_writing=true, keep_existing_content=false);
		defer file_close(*edfile);
		if runinfo.create_mode {
			apltime := current_time_consensus();
			ct := to_calendar(current_time_consensus(), .LOCAL);
			file_write(*edfile, tprint("% ", jlfile_time_to_string(ct)));
		} else {
			for matched_records {
				file_write(*edfile, it.content);
				file_write(*edfile, "\n");
			}
			info.loaded = matched_records.count;
		}
	}
	tempfile_before_edit := read_entire_file(edit_file); defer free(tempfile_before_edit);
	before_sha := sha256(tempfile_before_edit);

	// ** begin and wait for editting
	if !create_process(*process_edit, editor_str, edit_file) {
		log_error("Failed to edit file: % %", editor_str, edit_file);
		return;
	}
	while true {
		good, result := get_process_result(*process_edit);
		if !(good && result.type == .STILL_RUNNING) {
			break;
		}
		sleep_milliseconds(1000/30);
	}

	// ** save the file
	editted_jlfile_raw := read_entire_file(edit_file,,temp);
	editted_jlfile := jlfile_parse(editted_jlfile_raw);
	defer jlfile_release(*editted_jlfile);

	editted_sha := sha256(editted_jlfile_raw);
	for 0..31 {
		if before_sha[it] != editted_sha[it] break;
		if it == 31 {
			print("Didn't change anything.");
			exit(0);
		}
	}

	info.editted = editted_jlfile.records.count;
	defer file_delete(edit_file);

	if info.editted == 0 {
		log("Found 0 record, exit without saving...");
	} else {
		sb : String_Builder;
		init_string_builder(*sb); defer free_buffers(*sb);

		for * jlfile.records {
			if !runinfo.create_mode && !it.exclude continue;
			append(*sb, it.content);
			append(*sb, "\n");
		}
		for * editted_jlfile.records {
			append(*sb, it.content);
			append(*sb, "\n");
		}
		content := builder_to_string(*sb); defer free(content);

		ftarget := file_open(runinfo.target_file, for_writing=true, keep_existing_content=false);
		if runinfo.file_is_encrypted {
			file_write(*ftarget, cast(string)JLMAGIC);
			encrypted := jl_encrypt(xx content, runinfo.password_sha256);
			file_write(*ftarget, cast(string)encrypted);
		} else {
			file_write(*ftarget, content);
		}
		file_close(*ftarget);

		deleted := info.loaded-info.editted;
		log("Load %/% records, save % records.%", info.loaded, info.all, info.editted,
			ifx deleted>1 then tprint(" % records are deleted.", deleted) else (ifx deleted>0 then " 1 record is deleted." else "")
		);
	}
}

operation_print :: () {
	for < matched_records {
		time    := slice(it.content, 0, 24);
		content := slice(it.content, 24, it.content.count-24);
		print("\e[33m%\e[39m%\n", time, content);
	}
}

operation_list_tags :: () {
	// TODO:
	print("Haven't done yet. Here's all the titles:\n");
	for matched_records {
		_, left, _ := split_from_left(it.content, #char "\n");
		print("%\n", left);
	}
}

operation_decrypt :: () {
	using runinfo;
	filecontent, read_ok := read_entire_file(target_file);
	if !read_ok {
		print("Failed to read target file: %.", target_file);
		return;
	}
	if !is_data_jl_encrypted(xx filecontent) {
		print("File is plaintext, you don't need to decrypt.\n");
		return;
	}
	
	if !try_get_stored_key(*password_sha256) {
		print("Password:");
		password_sha256 = sha256(read_pswd(allocator=temp));
	}

	decrypted_data, dec_ok := jl_decrypt(xx slice(filecontent, JLMAGIC.count, filecontent.count-JLMAGIC.count), password_sha256);
	defer array_free(decrypted_data);
	if !dec_ok {
		print("Wrong password!\n");
		return;
	}

	file := file_open(target_file, for_writing=true);
	file_write(*file, cast(string)decrypted_data);
	file_close(*file);
	print("Plain text jl file saved to %.\n", target_file);

	keypath := get_jl_filepath("default.key", temp);
	if file_exists(keypath) {
		file_delete(keypath);
		print("Old key file % deleted.\n", keypath);
	}
}

operation_encrypt :: (save_key: bool) {
	using runinfo;
	filecontent, read_ok := read_entire_file(target_file);
	if !read_ok {
		print("Failed to read target file: %.", target_file);
		return;
	}
	if is_data_jl_encrypted(xx filecontent) {
		print("why don't you go here\n");
		print(#string DONE
File is already encrypted, if you want to change the password, you 
can --decrypt it first, then encrypt again.
DONE);
		return;
	}

	print("Password:");
	password := read_pswd(allocator=temp);
	password_sha256 = sha256(password);
	print("Repeat password:");
	repeat := read_pswd(allocator=temp);
	if password != repeat {
		print("Please input the same password!\n");
	} else {
		encrypted_data := jl_encrypt(xx filecontent, password_sha256);
		defer array_free(encrypted_data);
		file := file_open(target_file, for_writing=true);
		file_write(*file, cast(string)JLMAGIC);
		file_write(*file, cast(string)encrypted_data);
		file_close(*file);
		print("Encrypted jl file saved to %.\n", target_file);
		if save_key {
			keypath := get_jl_filepath("default.key", temp);
			write_entire_file(keypath, cast(string)sha256_raw_to_hex(password_sha256));
			print("Key saved to %\n", keypath);
		}
	}
}

file_exists :: (path: string) -> bool {
	f, ok := file_open(path); defer file_close(*f);
	return ok;
}

try_get_stored_key :: (outkey: *[32]u8) -> bool {
	keypath := get_jl_filepath("default.key", temp);

	f, fopenok := file_open(keypath);
	if !fopenok  return false; 
	file_close(*f);

	hexkey, ok := read_entire_file(keypath);
	assert(hexkey.count == 64);
	if !ok return false;
	rawkey, convert_ok := sha256_hex_to_raw(cast([64]u8)hexkey.data);
	if !convert_ok return false;
	outkey.* = rawkey;
	return ok;
}

sha256 :: (str: string) -> [32]u8 {
	key: [32]u8;
	SHA256(str.data, xx str.count, *key[0]);
	return key;
}

#import,dir "modules/openssl";
#import "File";
#import "Basic";
#import "Sort";
#import "Process";

#if OS == .WINDOWS {
	Windows :: #import "Windows";
	getenv :: Windows.getenv;
}

JLMAGIC :[16]u8: xx "VMWVWWWVWWVMVWMM";

HELP_STRING :: #string DONE
`jl` is a journaling tool inspired by `jrnl`.
To use this, you should have these setups.

- `JLEDITOR` or `EDITOR` in environment.

- `JLDEFAULTFILE` in environment, specifying the file path. This 
is optional. By default the file will be in the user folder. You 
can see that path in the first line. And this is also temporary,
we will have a config file later. So that you can have multiple files.

Currently we only support tag filtering.
- jl @idea # search for records with @idea tagged in its title line.

And operations you have:
- jl --edit # this is the default operation.
- jl --print
- jl --tags # TODO yet

Or you can just type:
- jl # to create a new record.
DONE

is_data_jl_encrypted :: inline (data: []u8) -> bool {
	return begins_with(cast(string)data, cast(string)JLMAGIC);
}

get_encrypted_jlfile_cipher :: inline (data: []u8) -> []u8 {
	return array_view(data, JLMAGIC.count, data.count-JLMAGIC.count);
}

read_pswd :: #bake_arguments read_stdin(invisible=true);

#run {
	#import "Compiler";
	bo := get_build_options();
	debug := bo.null_pointer_check; // Check if you passed a `-release` when build.
	print("===\n");
	print("Building...\n");
	if debug {
		add_build_string("DEBUG :: true;", -1);
		print("Build the program in DEBUG mode.\n");
	} else {
		add_build_string("DEBUG :: false;", -1);
	}
	print("===\n");
}
