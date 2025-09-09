#load "args_reader.jai";
#load "config.jai";
#load "crypto.jai";
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

	filter_specified           : bool;
	operation_specified : bool;

	create_mode  : bool;

	operation    : OperationMode;
	OperationMode :: enum u8 {
		Edit;
		ListTags;
		Print;
	}
}

main :: () {
	#if false {
		secret : string;
		assert(test_encryption(*secret));
		print("secret:\n%\n", secret);
	}

	args := get_command_line_arguments();

	jlfolder := get_jl_directory();
	make_directory_if_it_does_not_exist(jlfolder);

	// @Temporary: We will have a config file.
	runinfo.target_file = to_string(getenv("JLDEFAULTFILE"));
	if runinfo.target_file.data == null {
		runinfo.target_file = get_jl_filepath("default.jl"); // No free!
	}
	print("Load jlfile from '%' .\n", runinfo.target_file);

	// ** load file
	file_content, file_read_good := read_entire_file(runinfo.target_file);
	if !file_read_good {
		// TODO: create the file.
		log_error("Can't read file '%' .", runinfo.target_file);
		exit(1);
	}
	jlfile = jlfile_parse(file_content); defer jlfile_release(*jlfile);
	info.all = jlfile.records.count;

	tags : [..]string; defer free(tags.data);

	runinfo.create_mode = args.count == 1;
	// NOTE: If the filter is not specified, we load all the records.
	// Running `jl` with no argument, will lead to create mode.
	for args {
		if it_index == 0 continue;
		if it[0] == #char "@" {
			array_add(*tags, it);
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
			print(
#string DONE
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
DONE);
			exit(0);
		} else {
			print("Unknown arguments.\n");
			exit(0);
		}
	}

	if runinfo.filter_specified {
		for * jlfile.records {
			_, title_line, _ := split_from_left(it.content, #char "\n");
			for tag: tags {
				if contains(title_line, tag) {
					array_add(*matched_records, it);
				} else {
					it.exclude = true;
				}
			}
		}
	} else {
		for * jlfile.records array_add(*matched_records, it);
	}

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
			ct := to_calendar(current_time_consensus());
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
		ftarget := file_open(runinfo.target_file, for_writing=true, keep_existing_content=false);
		defer file_close(*ftarget);
		for jlfile.records {
			if !runinfo.create_mode && !it.exclude continue;
			file_write(*ftarget, it.content);
			file_write(*ftarget, "\n");
		}
		for editted_jlfile.records {
			file_write(*ftarget, it.content);
			file_write(*ftarget, "\n");
		}
		deleted := info.loaded-info.editted;
		log("Load %/% records, save % records.%", info.loaded, info.all, info.editted,
			ifx deleted>1 then tprint(" % records are deleted.", deleted) else (ifx deleted>0 then " 1 record is deleted." else "")
		);
	}
}

operation_print :: () {
	for matched_records {
		print("%\n", it.content);
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

sha256 :: (str: string) -> [32]u8 {
	key: [32]u8;
	SHA256(str.data, xx str.count, *key[0]);
	return key;
}

#import,dir "modules/openssl";
#import "File";
#import "Basic";
#import "Process";

#if OS == .WINDOWS {
	Windows :: #import "Windows";
	getenv :: Windows.getenv;
}
