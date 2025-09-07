#import "File";
#import "String";


#if OS == .WINDOWS {
	PATHSEP :: "\\";
} else {
	PATHSEP :: "/";
}

get_jl_directory :: () -> string {
	if jl_folder.data == null jl_folder = join(get_user_data_directory(), "jl", separator=PATHSEP);
	return jl_folder; // No need to free.
}

get_jl_filepath :: (filename: string, allocator:=context.allocator) -> string {
	return join(get_jl_directory(), filename, separator=PATHSEP);
}

get_user_data_directory :: () -> string {
#if OS == .WINDOWS {
	return to_string(getenv("LOCALAPPDATA"));
}
}

#scope_file;

jl_folder : string;
