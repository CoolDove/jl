// Hidden feature: keep a small rolling set of backups of the jl file in the
// system temp directory. A backup is taken right before every change, and the
// bytes are copied verbatim, so an encrypted file keeps encrypted backups.

#import "File";
#import "String";
#import "Basic";
#import "Sort";

Backup_File :: #import "File_Utilities";

BACKUP_MAX_COUNT :: 5;
BACKUP_DIRECTORY_NAME :: "jl_backups";
BACKUP_EXTENSION :: ".jl";

backup_directory :: () -> string {
	return join(system_temp_directory(), BACKUP_DIRECTORY_NAME, separator=PATHSEP);
}

system_temp_directory :: () -> string {
	#if OS == .WINDOWS {
		value := getenv("TEMP");
		if value == null value = getenv("TMP");
		if value != null {
			path := to_string(value);
			if path.count > 0 return path;
		}
	}
	return get_jl_directory();
}

// Identifies the jl file that a backup belongs to, so that backups of
// different jl files never prune each other.
backup_key :: (target_file: string) -> string {
	absolute, ok := get_absolute_path(target_file);
	if !ok absolute = target_file;
	digest := sha256(absolute);

	builder : String_Builder;
	init_string_builder(*builder, 8);
	defer free_buffers(*builder);

	HEX :: "0123456789abcdef";
	for 0..3 {
		byte := digest[it];
		append(*builder, HEX[xx (byte >> 4)]);
		append(*builder, HEX[xx (byte & 15)]);
	}
	return builder_to_string(*builder);
}

// File name prefix of the backups of one jl file, e.g. "dove-c83ae05a-".
backup_prefix :: (target_file: string) -> string {
	_, basename, _, _ := path_decomp(target_file);
	return tprint("%-%", basename, backup_key(target_file));
}

backup_timestamp :: (ct: Calendar_Time) -> string {
	digits :: #bake_arguments formatInt(minimum_digits = 2);
	return sprint("%-%-%-%-%-%",
		ct.year,
		digits(ct.month_starting_at_0 + 1),
		digits(ct.day_of_month_starting_at_0 + 1),
		digits(ct.hour),
		digits(ct.minute),
		digits(ct.second));
}

Backup_Entry :: struct {
	path    : string;
	modtime : Apollo_Time;
}

// Returns the backups of `target_file`, or all backups when `all` is set.
// The caller owns the returned strings.
backup_entries :: (target_file: string, all := false) -> [..]Backup_Entry {
	entries : [..]Backup_Entry;
	dir := backup_directory();
	if !Backup_File.file_exists(dir) return entries;

	key : string;
	if !all {
		key = tprint("%-", backup_prefix(target_file));
	}

	names := Backup_File.file_list(dir);
	defer {
		for names free(it);
		free(names.data);
	}

	for names {
		_, basename, _, _ := path_decomp(it);
		if !all && !begins_with(basename, key) continue;
		modtime, _, ok := Backup_File.file_modtime_and_size(it);
		if !ok continue;
		array_add(*entries, Backup_Entry.{copy_string(it), modtime});
	}
	return entries;
}

free_backup_entries :: (entries: *[..]Backup_Entry) {
	for entries.* free(it.path);
	free(entries.data);
}

sort_backups_newest_first :: (entries: *[..]Backup_Entry) {
	quick_sort(entries.*, (a: Backup_Entry, b: Backup_Entry) -> int {
		if a.modtime > b.modtime return -1;
		if a.modtime < b.modtime return  1;
		return 0;
	});
}

// Copies the current content of `target_file` into the backup directory and
// keeps only the newest BACKUP_MAX_COUNT backups of that file.
backup_current_file :: (target_file: string) -> bool {
	data, read_ok := read_entire_file(target_file, log_errors=false);
	if !read_ok return false;
	defer free(data);

	dir := backup_directory();
	if !make_directory_if_it_does_not_exist(dir) return false;

	prefix := backup_prefix(target_file);
	timestamp := backup_timestamp(now);
	path : string;
	for 0..99 {
		suffix := ifx it == 0 then "" else tprint("-%", it);
		filename := join(prefix, "-", timestamp, suffix, BACKUP_EXTENSION, separator="");
		path = join(dir, filename, separator=PATHSEP);
		if !Backup_File.file_exists(path) break;
	}

	if !write_entire_file(path, data) {
		log_error("Failed to save the backup '%'.", path);
		return false;
	}

	entries := backup_entries(target_file);
	defer free_backup_entries(*entries);
	sort_backups_newest_first(*entries);
	for entries {
		if it_index < BACKUP_MAX_COUNT continue;
		file_delete(it.path);
	}
	return true;
}

operation_backup_list :: () {
	entries := backup_entries("", all = true);
	defer free_backup_entries(*entries);
	if entries.count == 0 {
		print("No backups.\n");
		return;
	}
	sort_backups_newest_first(*entries);
	for entries print("%\n", it.path);
}

operation_backup_clear :: () {
	entries := backup_entries("", all = true);
	defer free_backup_entries(*entries);
	for entries file_delete(it.path);
	print("Deleted % backups.\n", entries.count);
}
