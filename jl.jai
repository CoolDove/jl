JlRecord :: struct {
	time : Calendar_Time;
	content : string;
	// runtime
	exclude : bool;
}
JlFile :: struct {
	records : []JlRecord;
}

jlfile_parse :: (src: string, allocator:=context.allocator) -> JlFile {
	push_allocator(allocator);

	handler :Text_File_Handler=.{
		comment_character = 0, // Dont support commenting.
		do_version_number = false, // Dont check the version number on the file.
		auto_skip_blank_lines = false,
	};
	defer deinit(*handler);

	records : [..]JlRecord;
	buffer : String_Builder;

	init_string_builder(*buffer);
	defer free_buffers(*buffer);

	start_from_memory(*handler, "jlfile", "???", src);

	SUBMIT_CURRENT :: () #expand {
		if builder_string_length(*buffer) > 0 {
			str := builder_to_string(*buffer);
			if str[str.count-1] == "\n" {
				str = trim_right(str, "\n");
				str.count += 1;
			}
			record := JlRecord.{
				time = time,
				content = str,
			};
			array_add(*records, record);
		}
	}

	time : Calendar_Time;
	while !handler.failed {
		line, found := consume_next_line(*handler);
		if !found break;
		if trim(line) != "" && line[0] == #char "[" && try_parse_calender_time(line, *time) {
			// ** upload current
			SUBMIT_CURRENT();
		}
		print_to_builder(*buffer, line);
		print_to_builder(*buffer, "\n");
	}
	SUBMIT_CURRENT();
	return .{records};
}

jlfile_release :: (file: *JlFile) {
	free(file.records.data);
}

jlfile_parse_time :: (str: string) -> Calendar_Time, bool {
	ct : Calendar_Time;
	good := try_parse_calender_time(str, *ct);
	return ct, good;
}
jlfile_time_to_string :: time_to_string;

#import "String";
#import "Basic";
#import "Text_File_Handler";

#scope_file;
rune :: #type s64;
try_parse_calender_time :: (str: string, to: *Calendar_Time) -> bool {
	if str.count < 24 return false;
	if str[0]  != "[" return false;
	if str[23] != "]" return false;

	s := slice(str, 1, 22);

	step :: () -> u8 #expand { ns := s[0]; `s.data += 1; `s.count -= 1; return ns; };
	step_digits :: (n: int) -> bool #expand {
		for 0..n-1 if !is_digit(step()) return false;
		return true;
	}
	step_slash :: () -> bool #expand {
		return step() == #char "-";
	}
	step_semi :: () -> bool #expand {
		return step() == #char ":";
	}
	step_space :: () -> bool #expand {
		return step() == #char " ";
	}

	if !step_digits(4) return false;
	if !step_slash() return false;
	if !step_digits(2) return false;
	if !step_slash() return false;
	if !step_digits(2) return false;

	if !step_space() return false;

	if !step_digits(2) return false;
	if !step_semi() return false;
	if !step_digits(2) return false;
	if !step_semi() return false;
	if !step_digits(2) return false;

	if !step_space() return false;

	if !(s == "AM" || s == "PM" || s == "am" || s == "pm") return false;

	calendar_str := slice(str, 0, 24);
	int_since :: (idx: int) -> int #expand {
		str := slice(calendar_str, idx, calendar_str.count);
		return parse_int(*str);
	}

	ct : Calendar_Time;
	ct.year = xx int_since(1);
	ct.month_starting_at_0 = xx int_since(6);
	ct.day_of_month_starting_at_0 = xx int_since(9);
	ct.hour = xx int_since(12);
	ct.minute = xx int_since(15);
	ct.second = xx int_since(18);
	if s == "PM" || s == "pm" ct.hour += 12;

	to.* = to_calendar(calendar_to_apollo(ct));// to reset the 
	return true;
}

time_to_string :: (ct: Calendar_Time, allocator:=temp) -> string {
	push_allocator(allocator);
	hhour := ct.hour%12;
	pm := ct.hour > 11;
	date_part :: #bake_arguments formatInt(minimum_digits = 2);
	using ct;
	return sprint("[%-%-% %:%:% %]",
		year,
		date_part(month_starting_at_0 + 1),
		date_part(day_of_month_starting_at_0 + 1),
		date_part(hhour),
		date_part(minute),
		date_part(second),
		ifx pm then "PM" else "AM"
	);
}
