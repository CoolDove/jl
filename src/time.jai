// Both `month`, `day` and `weekday` starts from 0.
Date :: struct {
	year:int;
	month:int;
	day:int;
}

get_weekday :: (year:int, month:int, day:int) -> int #no_context {
	t := int.[0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4];
	if month < 2 {
		year -= 1;
	}
	day += 1;
	return (year + year/4 - year/100 + year/400 + t[month] + day) % 7;
}
is_date_valid :: (year:int, month:int, day:int) -> bool {
	if month < 0 || month > 11 return false;
	if day < 0 || day >= days_in_month(year, month) return false;
	return true;
}
is_same_day :: (a: Calendar_Time, b: Calendar_Time) -> bool #no_context {
	return
	a.year == b.year
	&& a.month_starting_at_0 == b.month_starting_at_0
	&& a.day_of_month_starting_at_0 == b.day_of_month_starting_at_0;
}

is_time_valid :: (year:int, month:int, day:int) -> bool {
	if month < 0 || month > 11 return false;
	if day < 0 || day >= days_in_month(year, month) return false;
	return true;
}

is_leap_year :: (year: int) -> bool #no_context {
	if year % 400 == 0 return true;
	if year % 100 == 0 return false;
	if year % 4 == 0 return true;
	return false;
}
days_in_year :: inline (year: int) -> int #no_context {
	return ifx is_leap_year(year) then 366 else 365;
}
days_in_month :: inline (year: int, month: int) -> int {
	assert(month >= 0 && month < 12, "Invalid month number, should be in [0, 11]");
	if is_leap_year(year) && month == 1 return 29;
	days_in_months :: int.[31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
	return days_in_months[month];
}

get_tomorrow :: (calendar: Calendar_Time) -> Calendar_Time {
	result := calendar;
	result.day_of_month_starting_at_0 += 1;
	if result.day_of_month_starting_at_0 > days_in_month(result.year, result.month_starting_at_0) {
		result.day_of_month_starting_at_0 = 0;
		result.month_starting_at_0 += 1;
		if result.month_starting_at_0 > 11 {
			result.month_starting_at_0 = 1;
			result.year += 1;
		}
	}
	result.day_of_week_starting_at_0 = xx get_weekday(result);
	return result;
}

total_days :: (date: Date) -> int {
	days : int;
	for 0..date.year-1 {
		days += days_in_year(it);
	}
	for 0..date.month-1 {
		days += days_in_month(date.year, it);
	}
	return days + date.day;
}

date_from_calendar :: (ct: Calendar_Time) -> Date {
	return Date.{ct.year, ct.month_starting_at_0, ct.day_of_month_starting_at_0};;
}
date_from_total_days :: (days: int) -> Date {
	d := days;
	year := 0;
	while true {
		year_days := days_in_year(year);
		if d < year_days {
			break;
		}
		year += 1;
		d -= year_days;
	}
	month := 0;
	while true {
		month_days := days_in_month(year, month);
		if d < month_days {
			break;
		}
		month += 1;
		d -= month_days;
	}
	return .{year, month, d};
}

date_offset :: (date: Date, days: int) -> Date {
	total := total_days(date);
	total += days;
	return date_from_total_days(total);
}

#scope_file;
get_weekday :: inline (ct: Calendar_Time) -> int {
	return get_weekday(ct.year, ct.month_starting_at_0, ct.day_of_month_starting_at_0);
}
