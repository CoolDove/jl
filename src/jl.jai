JlRecord :: struct {
	time : Calendar_Time;
	apollo_time : Apollo_Time;
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
				apollo_time = apollo_time,
				content = str,
			};
			array_add(*records, record);
		}
	}

	time : Calendar_Time;
	apollo_time : Apollo_Time;
	while !handler.failed {
		line, found := consume_next_line(*handler);
		if !found break;
		next_time : Calendar_Time;
		next_apollo_time : Apollo_Time;
		if trim(line) != "" && line[0] == #char "[" && try_parse_calender_time(line, *next_time, *next_apollo_time) {
			// ** upload current
			SUBMIT_CURRENT();
			time = next_time;
			apollo_time = next_apollo_time;
		}
		print_to_builder(*buffer, line);
		print_to_builder(*buffer, "\n");
	}
	SUBMIT_CURRENT();
	return .{records};
}

jlfile_release :: (file: *JlFile) {
	for file.records free(it.content);
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
try_parse_calender_time :: (str: string, to: *Calendar_Time=null, to_apollo_time: *Apollo_Time=null) -> bool {
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
	ct.month_starting_at_0 = xx (int_since(6)-1);
	ct.day_of_month_starting_at_0 = xx (int_since(9)-1);
	ct.hour = xx int_since(12);
	ct.minute = xx int_since(15);
	ct.second = xx int_since(18);
	if s == "PM" || s == "pm" ct.hour += 12;

	// TODO: Maybe i can optimize this, and handle the error.
	apl_time, time_valid := jlfile_calendar_to_apollo(ct);
	if !time_valid {
		log_error("\e[35mInvalid time found:\e[39m %\n", jlfile_time_to_string(ct));
	}
	if to_apollo_time != null {
		to_apollo_time.* = apl_time;
	}
	if to != null {
		to.* = to_calendar(apl_time);// to reset the weekday
	}
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

jlfile_calendar_to_apollo :: (ct: Calendar_Time) -> Apollo_Time, bool {
	#if OS == .WINDOWS {
		// @Incomplete.  See :OSSpecific
		result: Apollo_Time = ---;

		W :: #import "Windows";

		st: W.SYSTEMTIME;
		st.wYear      = xx,trunc ct.year;
		st.wMonth     = xx,trunc (ct.month\      _starting_at_0 + 1);
		st.wDay       = xx,trunc (ct.day_of_month_starting_at_0 + 1);
		st.wDayOfWeek = xx,trunc ct .day_of_week\_starting_at_0;
		st.wHour      = xx,trunc ct.hour;
		st.wMinute    = xx,trunc ct.minute;
		st.wSecond    = xx,trunc ct.second;
		st.wMilliseconds = xx,trunc ct.millisecond;

		ft: FILETIME;
		success := W.SystemTimeToFileTime(*st, *ft);
		if success == .FALSE return current_time_consensus(), false;

		if ct.time_zone == .LOCAL {
			ft_local: FILETIME;
			success := W.LocalFileTimeToFileTime(*ft, *ft_local);
			if success ft = ft_local;
			assert(success != .FALSE);
		}

		apollo := filetime_to_apollo(ft);
		return apollo, success == .TRUE;
	} else {
		return calendar_to_string(ct), true;
	}
}
