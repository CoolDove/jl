#run {
	add_build_file("src/main.jai", -1);

	dc :Build_Options_During_Compile= .{
		output_executable_name = "jl"                // If nonempty, gets copied to Build_Options.output_executable_name.
	};
	#if OS == .WINDOWS {
		dc.append_linker_arguments = .["/IGNORE:4099"]; // These just get appended to Build_Options.additional_linker_arguments. See the note there. This will not override any pre-existing arguments in Build_Options.
	}
	set_build_options_dc( dc );
};

#import "Basic";
#import "Compiler";
