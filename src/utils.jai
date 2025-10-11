region_timer :: (tag:string="", $debug_only:=true) #expand {
	#if debug_only && DEBUG {
		begin := current_time_consensus();
		`defer {
			end := current_time_consensus();
			d := end - begin;
			#if debug_only {
				print_time_duration(tprint("DEBUG-ONLY:%", tag), d);
			} else {
				print_time_duration(tag, d);
			}
		}
	}
}

MiniTimer :: struct {
	time : Apollo_Time;
	tag  : string;
}
timer_begin :: (tag: string) -> MiniTimer #expand {
	return .{current_time_consensus(), tag};
}
timer_end :: inline (t: *MiniTimer) {
	d := current_time_consensus() - t.time;
	print_time_duration(t.tag, d);
}

string_by_line :: (s: *string, code: Code, flags: For_Flags) #expand {
	#assert flags == 0 "Doesn't support flags.";
	idx : int;
	current : string;
	current.data = s.data;

	for v,n :s.* {
		if v == "\n" {
			`it := current;
			`it_index := idx;
			#insert code;
			current.data = s.data + n + 1;
			current.count = 0;
			idx += 1;
		} else {
			current.count += 1;
		}
	}
}

find_substring :: (s: string, substring: string) -> s64 {
	point :s64= 0;
	for i: 0..s.count-1 {
		if s[i] == substring[point] {
			point += 1;
			if point == substring.count {
				return i - point + 1;
			}
		} else {
			point = 0;
		}
	}
	return -1;
}

SubstrIte :: struct {
	s  : string;
	sub: string;
}
substr_ite :: (s: string, substr: string) -> SubstrIte {
	return .{ s, substr };
}
for_expansion :: (ite: *SubstrIte, code: Code, flags: For_Flags) #expand {
	using ite;
	point :s64= 0;
	idx := 0;
	for i: 0..s.count-1 {
		if s[i] == sub[point] {
			point += 1;
			if point == sub.count {
				// The `it` is the position of the match starts. Cuz returning
				// the substring that you already know doesn't make sense.
				`it := i-point+1;
				`it_index := idx;
				`it_match := slice(s, i-point+1, sub.count);
				#insert code;
				point = 0;
				idx += 1;
			}
		} else {
			point = 0;
		}
	}
}

#scope_file;
print_time_duration :: (tag: string, d: Apollo_Time) {
	milliseconds := (d/1_000_000_000_000).low;
	if milliseconds == 0 {
		us := (d/1_000_000_000).low;
		print("%: % us.\n", tag, us);
	} else {
		print("%: % ms.\n", tag, milliseconds);
	}
}
