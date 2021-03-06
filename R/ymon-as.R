#' Coerce to year month
#'
#' @description
#' - Date, POSIXct, and POSIXlt are converted directly by extracting the year
#'   and month from `x`. Any day, hour, minute, or second components are
#'   dropped. Time zone information is not retained.
#'
#' - Integer and double input are assumed to be the number of months since the
#'   Unix origin of 1970-01-01.
#'
#' - Character input is assumed to be provided in a format containing only
#'   information about the year and month, such as `"1970-01"` or `"Jan 1970"`.
#'   It is parsed using the defaults of [ymon_parse()].
#'
#' @param x `[vector]`
#'
#'   An object to coerce to ymon.
#'
#' @param ...
#'
#'   Not used.
#'
#' @export
#' @examples
#' # Extra information such as days, hours, or time zones are dropped
#' as_ymon(as.Date("2019-05-03"))
#' as_ymon(as.POSIXct("2019-03-04 01:01:01", tz = "America/New_York"))
#'
#' # Integers are interpreted as the number of months since 1970-01-01
#' as_ymon(0L)
#' as_ymon(12L)
as_ymon <- function(x, ...) {
  UseMethod("as_ymon")
}

# ------------------------------------------------------------------------------

#' @export
as_ymon.default <- function(x, ...) {
  ellipsis::check_dots_empty()
  class <- class_collapse(x)
  abort(paste0("Can't convert a <", class, "> to a <ymon>."))
}

# ------------------------------------------------------------------------------

#' @export
as_ymon.ymon <- function(x, ...) {
  ellipsis::check_dots_empty()
  x
}

# ------------------------------------------------------------------------------

#' @rdname as_ymon
#' @export
as_ymon.Date <- function(x, ...) {
  ellipsis::check_dots_empty()
  force_to_ymon_from_date(x)
}

force_to_ymon_from_date <- function(x) {
  out <- warp_distance(x, period = "month")
  out <- as.integer(out)
  out <- new_ymon(out)
  names(out) <- names(x)
  out
}

# ------------------------------------------------------------------------------

#' @rdname as_ymon
#' @export
as_ymon.POSIXct <- function(x, ...) {
  ellipsis::check_dots_empty()
  force_to_ymon_from_posixct(x)
}

force_to_ymon_from_posixct <- function(x) {
  force_to_ymon_from_posixt(x)
}

force_to_ymon_from_posixt <- function(x) {
  # Drop time zone to avoid any DST weirdness in the
  # `warp_distance(period = "month")` call
  out <- as.Date(x)
  out <- force_to_ymon_from_date(out)
  out
}

# ------------------------------------------------------------------------------

#' @rdname as_ymon
#' @export
as_ymon.POSIXlt <- function(x, ...) {
  ellipsis::check_dots_empty()
  force_to_ymon_from_posixlt(x)
}

force_to_ymon_from_posixlt <- function(x) {
  out <- force_to_ymon_from_posixt(x)

  # `as.Date.POSIXlt()` used in `force_to_ymon_from_posixt()`
  # doesn't retain names! Bug!
  names(out) <- names(x)

  out
}

# ------------------------------------------------------------------------------

#' @rdname as_ymon
#' @export
as_ymon.integer <- function(x, ...) {
  ellipsis::check_dots_empty()
  force_to_ymon_from_integer(x)
}

force_to_ymon_from_integer <- function(x) {
  new_ymon(x)
}

# ------------------------------------------------------------------------------

#' @rdname as_ymon
#' @export
as_ymon.double <- function(x, ...) {
  ellipsis::check_dots_empty()
  force_to_ymon_from_double(x)
}

force_to_ymon_from_double <- function(x) {
  out <- vec_cast(x, integer())
  out <- new_ymon(out)

  # `vec_cast()` currently doesn't always keep names
  names(out) <- names(x)

  out
}

# ------------------------------------------------------------------------------

#' @rdname as_ymon
#' @export
as_ymon.character <- function(x, ...) {
  ellipsis::check_dots_empty()
  force_to_ymon_from_character(x)
}

# Strict parsing of character to ymon, expecting only the
# form YYYY-MM. Intended to roundtrip `as.character.ymon()`.
# Use `ymon_parse()` for more flexible handling.
force_to_ymon_from_character <- function(x) {
  na <- is.na(x)

  # Check for a dash
  has_dash_or_na <- grepl("-", x) | na
  missing_dash_and_not_na <- !has_dash_or_na

  if (any(missing_dash_and_not_na)) {
    locations <- which(missing_dash_and_not_na)
    stop_lossy_parse(locations, "Input must have a dash separator.")
  }

  split <- strsplit(x, "-", fixed = TRUE)

  # Check that there was only a single dash.
  # Total lengths should be `2 * length(x) - sum(na)`.
  lengths <- lengths(split, use.names = FALSE)
  real_length <- sum(lengths)
  expected_length <- 2L * length(x) - sum(na)

  if (real_length != expected_length) {
    ok <- map_lgl(split, function(x) length(x) == 2)
    ok <- ok | na
    locations <- which(!ok)
    stop_lossy_parse(locations, "Input must only have one dash separator.")
  }

  # Replace NA splits with c(NA, NA) to make extraction simpler
  split[na] <- list(c(NA_character_, NA_character_))

  chr_year <- map_chr(split, `[[`, i = 1L)
  chr_month <- map_chr(split, `[[`, i = 2L)

  # Go through double, then to integer to catch things like `2019.5-01`
  year <- suppressWarnings(as.double(chr_year))
  month <- suppressWarnings(as.double(chr_month))

  # Catch what can't be parsed as double
  not_ok <- is.na(year) | is.na(month)
  not_ok <- not_ok & !na

  if (any(not_ok)) {
    locations <- which(not_ok)
    stop_lossy_parse(locations, "Year and month components must be integers.")
  }

  # Finally cast double to integer
  year <- vec_cast(year, integer(), x_arg = "year")
  month <- vec_cast(month, integer(), x_arg = "month")

  out <- ymon(year, month)
  names(out) <- names(x)

  out
}

stop_lossy_parse <- function(locations, bullet = NULL) {
  if (length(locations) > 5) {
    locations <- c(locations[1:5], "etc.")
    full_stop <- ""
  } else {
    full_stop <- "."
  }

  if (length(locations) == 1L) {
    chr_location <- "location"
  } else {
    chr_location <- "locations"
  }

  locations <- paste0(locations, collapse = ", ")

  message <- paste0(
    "Unable to parse to ymon at ",
    chr_location,
    " ",
    locations,
    full_stop
  )

  if (!is.null(bullet)) {
    bullet <- format_error_bullets(c(x = bullet))
    message <- paste(c(message, bullet), collapse = "\n")
  }

  abort(message)
}

# ------------------------------------------------------------------------------

#' @export
as.Date.ymon <- function(x, ...) {
  ellipsis::check_dots_empty()
  force_to_date_from_ymon(x)
}

force_to_date_from_ymon <- function(x) {
  out <- months_to_days(x)
  out <- as.double(out)
  out <- new_date(out)
  names(out) <- names(x)
  out
}

# ------------------------------------------------------------------------------

#' @export
as.POSIXct.ymon <- function(x, tz = "UTC", ...) {
  ellipsis::check_dots_empty()
  force_to_posixct_from_ymon(x, tz)
}

force_to_posixct_from_ymon <- function(x, tz) {
  force_to_posixt_from_ymon(x, tz, posixct = TRUE)
}

force_to_posixt_from_ymon <- function(x, tz, posixct) {
  x <- force_to_date_from_ymon(x)

  if (identical(tz, "UTC")) {
    force_to_utc_from_date(x, posixct)
  } else {
    force_to_zoned_from_date(x, tz, posixct)
  }
}

force_to_zoned_from_date <- function(x, tz, posixct) {
  # Going through character is the only way to
  # retain clock time in the new tz
  x <- as.character(x)

  if (posixct) {
    as.POSIXct(x, tz = tz)
  } else {
    as.POSIXlt(x, tz = tz)
  }
}

# Much faster than `force_to_zoned_from_date()` for the default case
force_to_utc_from_date <- function(x, posixct) {
  if (posixct) {
    as_utc_posixct_from_date(x)
  } else {
    as_utc_posixlt_from_date(x)
  }
}

# ------------------------------------------------------------------------------

#' @export
as.POSIXlt.ymon <- function(x, tz = "UTC", ...) {
  ellipsis::check_dots_empty()
  force_to_posixlt_from_ymon(x, tz)
}

force_to_posixlt_from_ymon <- function(x, tz) {
  force_to_posixt_from_ymon(x, tz, posixct = FALSE)
}

# ------------------------------------------------------------------------------

#' @export
as.character.ymon <- function(x, ...) {
  ellipsis::check_dots_empty()
  force_to_character_from_ymon(x)
}

force_to_character_from_ymon <- function(x) {
  # Avoid `formatC(character())` bug with zero-length input
  if (vec_size(x) == 0L) {
    out <- character()
    out <- set_names(out, names(x))
    return(out)
  }

  result <- months_to_year_month(x)
  year <- result[[1]]
  month <- result[[2]]

  negative <- year < 0

  if (any(negative, na.rm = TRUE)) {
    out_year <- formatC(abs(year), width = 4, flag = "0")
    out_year[negative] <- paste0("-", out_year[negative])
  } else {
    out_year <- formatC(year, width = 4, flag = "0")
  }

  out_month <- formatC(month, width = 2, flag = "0")

  out <- paste(out_year, out_month, sep = "-")

  if (anyNA(x)) {
    out[is.na(x)] <- NA_character_
  }

  names(out) <- names(x)

  out
}

# ------------------------------------------------------------------------------

#' @export
as.integer.ymon <- function(x, ...) {
  ellipsis::check_dots_empty()
  force_to_integer_from_ymon(x)
}

force_to_integer_from_ymon <- function(x) {
  out <- unclass(x)
  # Ensures attributes are dropped, but also sadly drops names
  out <- as.integer(out)
  names(out) <- names(x)
  out
}

# ------------------------------------------------------------------------------

#' @export
as.double.ymon <- function(x, ...) {
  ellipsis::check_dots_empty()
  force_to_double_from_ymon(x)
}

force_to_double_from_ymon <- function(x) {
  out <- unclass(x)
  # Ensures attributes are dropped, but also sadly drops names
  out <- as.double(out)
  names(out) <- names(x)
  out
}

# ------------------------------------------------------------------------------
# Helpers

# as.POSIXlt.Date() is unbearably slow, this is much faster.
# Note that this doesn't handle Dates with fractional days, which
# should be `trunc(x)`ed towards 0. For our usage, the Date comes
# from a ymon object, so it will never need truncation.
as_utc_posixlt_from_date <- function(x) {
  x <- unclass(x)
  x <- x * datea_global_seconds_in_day
  out <- as.POSIXlt(x, tz = "UTC", origin = datea_global_origin_posixct)
  out
}

as_utc_posixct_from_date <- function(x) {
  x <- unclass(x)
  x <- x * datea_global_seconds_in_day
  structure(x, tzone = "UTC", class = c("POSIXct", "POSIXt"))
}
