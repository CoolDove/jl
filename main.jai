#load "args_reader.jai";
#load "config.jai";
#load "jl.jai";

process_edit : Process;

jlfile : JlFile;

matched_records : [..]*JlRecord; // No need to free~

info : struct {
	all     : int;
	loaded  : int;
	editted : int;
}

main :: () {
	args := get_command_line_arguments();

	jlfolder := get_jl_directory();
	make_directory_if_it_does_not_exist(jlfolder);

	target_file :string= get_jl_filepath("default.jl"); defer free(target_file);

	// ** load file
	file_content, file_read_good := read_entire_file(target_file);
	if !file_read_good {
		// TODO: create the file.
		log_error("Can't read file %", target_file);
		exit(1);
	}
	jlfile = jlfile_parse(file_content); defer jlfile_release(*jlfile);
	info.all = jlfile.records.count;

	tags : [..]string; defer free(tags.data);
	for args {
		if it_index == 0 continue;
		if it[0] == #char "@" {
			array_add(*tags, it);
		}
	}
	if tags.count > 0 {
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
		for matched_records {
			file_write(*edfile, it.content);
			file_write(*edfile, "\n");
		}
		info.loaded = matched_records.count;
	}

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
	editted_jlfile := jlfile_parse(read_entire_file(edit_file,,temp));
	defer jlfile_release(*editted_jlfile);
	info.editted = editted_jlfile.records.count;
	defer file_delete(edit_file);

	if info.editted == 0 {
		log("Found 0 record, exit without saving...");
	} else {
		ftarget := file_open(target_file, for_writing=true, keep_existing_content=false);
		defer file_close(*ftarget);
		for jlfile.records {
			if !it.exclude continue;
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

#import "File";
#import "Basic";
#import "Process";

#if OS == .WINDOWS {
	Windows :: #import "Windows";
	getenv :: Windows.getenv;
}
