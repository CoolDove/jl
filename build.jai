#run {
	add_build_file("src/main.jai", -1);

	dc :Build_Options_During_Compile= .{
		output_executable_name = "jl"                // If nonempty, gets copied to Build_Options.output_executable_name.
	};
	#if OS == .WINDOWS {
		dc.append_linker_arguments = .["/IGNORE:4099"]; // These just get appended to Build_Options.additional_linker_arguments. See the note there. This will not override any pre-existing arguments in Build_Options.
	}
	set_build_options_dc( dc );

	// Resolve the version while building, and pass it into the program.
	add_build_string(tprint("JL_VERSION :: \"%\";", get_version_string()), -1);
};

// The version is the nearest tag reachable from the current commit.
// When building from a source package without git information, fall back to
// JL_VERSION_FALLBACK so packaging can never break the build.
get_version_string :: () -> string {
	#import "Process";
	#import "String";

	JL_VERSION_FALLBACK :: "v?.?";

	// Ask git in the directory of this build script, so the build works no
	// matter which directory the compiler was invoked from.
	source_directory := path_strip_filename(#file);

	result, output, error := run_command("git", "describe", "--tags", "--abbrev=0",
		working_directory = source_directory,
		capture_and_return_output = true);

	if result.type == .EXITED && result.exit_code == 0 {
		version := trim(output);
		if version.count > 0 {
			log("jl version: % (from git).", version);
			return version;
		}
	}

	log("jl version: git information unavailable (%/%), using fallback '%'.", result, trim(error), JL_VERSION_FALLBACK);
	return JL_VERSION_FALLBACK;
}

#import "Basic";
#import "Compiler";
#import "String";
