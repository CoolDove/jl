JlRecord :: struct {
	time : Calendar_Time;
	apollo_time : Apollo_Time;
	content : string; // Reallocated with default allocator, will be freed in `jlfile_release()`.
	special_timetag : Special_Time_Tag;

	// runtime
	exclude : bool;
}

Special_Time_Tag :: enum u8 {
	none;
	now;
}

JlFile :: struct {
	records : []JlRecord;
}

jlfile_parse :: (src: string, allocator:=context.allocator) -> JlFile {
	push_allocator(allocator);

	records : [..]JlRecord;
	buffer : String_Builder;

	init_string_builder(*buffer);
	defer free_buffers(*buffer);

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
				special_timetag = special_timetag,
			};
			array_add(*records, record);
		}
	}

	time : Calendar_Time;
	apollo_time : Apollo_Time;
	special_timetag : Special_Time_Tag;
	source := src;

	for:string_by_line line, idx:source {
		next_time : Calendar_Time;
		next_apollo_time : Apollo_Time;
		has_time_prefix := line != "" && trim(line) != "" && line[0] == #char "[";
		next_special_timetag : Special_Time_Tag;
		if has_time_prefix next_special_timetag = try_parse_special_time_tag(line);
		if next_special_timetag != .none {

			SUBMIT_CURRENT();

			// The real time is filled in when the edited file is saved.
			time = to_calendar(current_time_consensus(), .LOCAL);
			apollo_time, _ = jlfile_calendar_to_apollo(time);
			special_timetag = next_special_timetag;

		} else if has_time_prefix && try_parse_calendar_time(line, *next_time, *next_apollo_time) {

			SUBMIT_CURRENT();

			time = next_time;
			apollo_time = next_apollo_time;
			special_timetag = .none;

		}
		append(*buffer, line);
		append(*buffer, "\n");
	}
	SUBMIT_CURRENT();
	return .{records};
}

// Parse the special tag written at the very beginning of `line`, or `.none`.
// Matching is case-insensitive, e.g. `[now]`, `[NOW]` and `[Now]` all work.
try_parse_special_time_tag :: (line: string) -> (tag: Special_Time_Tag) {
	for enum_values_as_enum(Special_Time_Tag) {
		if it == .none continue;
		text := tprint("[%]", it);
		if line.count < text.count continue;
		if equal_nocase(slice(line, 0, text.count), text) return it;
	}
	return .none;
}

jlfile_release :: (file: *JlFile) {
	for file.records free(it.content);
	free(file.records.data);
}

jlfile_parse_time :: (str: string) -> Calendar_Time, bool {
	ct : Calendar_Time;
	good := try_parse_calendar_time(str, *ct);
	return ct, good;
}
jlfile_time_to_string :: time_to_string;

#import "String";
#import "Basic";
#import "Text_File_Handler";

#scope_file;
rune :: #type s64;
try_parse_calendar_time :: (str: string, to: *Calendar_Time=null, to_apollo_time: *Apollo_Time=null) -> bool {
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
	ct.hour = xx (int_since(12) % 12);
	ct.minute = xx int_since(15);
	ct.second = xx int_since(18);
	if s == "PM" || s == "pm" ct.hour += 12;

	time_valid := is_date_valid(ct.year, ct.month_starting_at_0, ct.day_of_month_starting_at_0);
	if !time_valid {
		log_error("\e[35mInvalid time found:\e[39m %\n", jlfile_time_to_string(ct));
	} else {
		ct.day_of_week_starting_at_0 = xx get_weekday(ct.year, ct.month_starting_at_0, ct.day_of_month_starting_at_0);
	}
	if to != null {
		to.* = ct;
	}
	if to_apollo_time != null {
		to_apollo_time.* = jlfile_calendar_to_apollo(ct);
	}

	#if DEBUG {
		apl_time_old, time_valid_old := jlfile_calendar_to_apollo(ct);
		msg :: "Time processing inconsistant with old version.";
		assert(time_valid == time_valid_old, msg);
		if to_apollo_time != null assert(apl_time_old == to_apollo_time.*, msg);
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
