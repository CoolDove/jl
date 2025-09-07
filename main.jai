#load "config.jai";
#load "jl.jai";

process_edit : Process;

main :: () {
	args := get_command_line_arguments();

	jlfolder := get_jl_directory();
	make_directory_if_it_does_not_exist(jlfolder, false);

	target_file :string= get_jl_filepath("default.jl", temp);
	log("The file: %\n", target_file);

	file_content, file_read_good := read_entire_file(target_file);
	if !file_read_good {
		log("Can't read file %", target_file);
		exit(1);
	}
	jlfile := jlfile_parse(file_content); defer jlfile_release(*jlfile);

	print("file content: % records\n", jlfile.records.count);
	for jlfile.records print("--- record at %\n%\n", jlfile_time_to_string(it.time,, temp), it.content);

	return;

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

	// return;

	if !create_process(*process_edit, editor_str, target_file) {
		log_error("Failed to edit file: % %", editor_str, target_file);
		return;
	}

	while true {
		good, result := get_process_result(*process_edit);
		if !(good && result.type == .STILL_RUNNING) {
			log("Process exited: %.", result);
			break;
		}
	}
}

#import "File";
#import "Basic";
#import "Process";

#if OS == .WINDOWS {
	Windows :: #import "Windows";
	getenv :: Windows.getenv;
}
