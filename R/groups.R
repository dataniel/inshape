#' Describe how groups are composed of roles
#'
#' A family, a household or a workplace is a group of rows, and each row
#' has a role in it: reference person, partner, child. The composition of
#' a group is how many of each role it has, and `describe_groups()` counts
#' the groups with each composition: "1 reference + 1 partner + 2 child:
#' 4,210", "1 child: 12". Like the transition table of
#' [describe_transitions()] it is the diagnosis itself: the impossible
#' groups show before any rule is written. Require a composition with
#' [ensure_counts()].
#'
#' The group is what the `group` columns say: a family id, or a family id
#' and a year for families over time. A missing role is a role of its own,
#' shown as `NA`.
#'
#' @param data A data frame or tibble, or a database or Arrow table: see
#'   *Database and Arrow tables* in [checkpoints].
#' @param group Column(s) identifying the group (tidy-select), e.g.
#'   `c(family, year)`.
#' @param role The role column (one column), e.g. `role`.
#'
#' @return An object of class `inshape_groups`, printed as a summary. It is
#'   a list with `group`, `role`, the counts `n_rows` and `n_groups`,
#'   `roles` (the roles, as text) and `compositions`, a tibble with one
#'   column per role holding its count, `composition` (the same as text) and
#'   `groups`, most common first.
#'
#' @examples
#' families <- data.frame(
#'   family = c(1, 1, 1, 2, 2, 3, 4, 4),
#'   role   = c("reference", "partner", "child", "reference", "child",
#'              "child", "reference", "reference")
#' )
#' # family 3 has no reference person, family 4 has two
#' describe_groups(families, family, role)
#'
#' @seealso [ensure_counts()] to require a composition,
#'   [ensure_references()] for rows that point to each other.
#'
#' @export
describe_groups <- function(data, group, role) {
  tbl <- check_table(data)
  groups <- select_names(tbl, {{ group }})
  role_col <- select_names(tbl, {{ role }})
  if (length(groups) == 0) cli::cli_abort("{.arg group} must select at least one column.")
  if (length(role_col) != 1) cli::cli_abort("{.arg role} must select exactly one column.")

  if (is_remote(tbl)) {
    tbl <- dplyr::ungroup(tbl)
    roles <- sort(dplyr::pull(dplyr::distinct(tbl, .data[[role_col]])), na.last = TRUE)
    check_role_count(roles)
    per_group <- remote_role_counts(tbl, groups, role_col, roles)
    cols <- names(per_group$exprs)
    comp <- per_group$query |>
      dplyr::count(!!!rlang::syms(cols), name = "groups") |>
      dplyr::collect()
    n_rows <- remote_nrow(tbl)
    counts <- lapply(comp[cols], as.numeric)
    n_by <- as.numeric(comp$groups)
  } else {
    gid <- group_ids(data, groups)
    roles_x <- data[[role_col]]
    rid <- dense_codes(roles_x)
    first <- first_row_by(rid, attr(rid, "n"))
    roles <- roles_x[first]
    o <- order(roles, na.last = TRUE, method = "radix")
    roles <- roles[o]
    check_role_count(roles)
    rid <- match(rid, o)
    m <- role_matrix(gid, rid, length(roles))
    comp_id <- group_ids(as.data.frame(m), names(as.data.frame(m)))
    k <- attr(comp_id, "n")
    firsts <- first_row_by(comp_id, k)
    seen <- which(firsts > 0L)
    counts <- lapply(seq_along(roles), function(j) as.numeric(m[firsts[seen], j]))
    n_by <- tabulate(comp_id, k)[seen]
    n_rows <- nrow(data)
  }
  labels <- fmt_values(roles)
  names(counts) <- labels
  comp <- tibble::as_tibble(counts)
  comp$composition <- composition_text(counts, labels)
  comp$groups <- n_by
  comp <- comp[order(-comp$groups, comp$composition), ]

  structure(list(group = groups, role = role_col, n_rows = n_rows,
                 n_groups = sum(n_by), roles = labels, compositions = comp),
            class = "inshape_groups")
}

#' @export
print.inshape_groups <- function(x, ...) {
  describe_header(
    paste0("Groups: ", toString(x$group), " by ", x$role),
    paste0(count(x$n_rows, "row"), ", ", count(x$n_groups, "group"), ", ",
           count(length(x$roles), "role"))
  )
  note_line(paste0("Compositions: ", big(nrow(x$compositions))))
  shown <- x$compositions[c("composition", "groups")]
  shown$share <- sprintf("%.1f%%", 100 * shown$groups / max(x$n_groups, 1))
  table_block("Most common compositions:", shown)
  invisible(x)
}

#' Assert how many rows of each role a group has
#'
#' A checkpoint for the composition of groups: a family has exactly one
#' reference person and at most two adults, a child has at most two
#' parents, a person dies at most once. The groups that break a limit are
#' reported, with every row of the group and a `broken` column naming the
#' limits broken, such as `"reference: 0 (needs 1)"`. Returns `data`, so it
#' can sit in the middle of a pipeline.
#'
#' Give the limits per role as a list, `list(reference = 1, adult = c(1, 2))`:
#' one number for an exact count, two for the least and the most, with
#' `Inf` for no upper limit. A group with no row of a role has 0 of it, so
#' a family without a reference person breaks `reference = 1`. Roles not
#' named are not limited. Without `role`, `limits` is one such number or
#' pair, for the number of rows per group.
#'
#' The same check covers relations and events: rows per child in a table
#' of parents (`limits = c(0, 2)`), and deaths per person in a table of
#' events (`role = event, limits = list(death = c(0, 1))`). To check a
#' composition per family type, such as single parents with one adult, run
#' it on the families of that type.
#'
#' @inheritParams describe_groups
#' @param role The role column (one column), or `NULL` to count rows.
#' @param limits A named list of limits per role, or without `role` a
#'   single limit: a number, or the least and the most as two numbers.
#' @inheritParams checkpoints
#' @param warn_msg Message shown when a group breaks a limit and no
#'   `abort_msg` is set. Defaults to a description of the check.
#'
#' @return `data` invisibly, unchanged.
#'
#' @examples
#' families <- data.frame(
#'   family = c(1, 1, 1, 2, 2, 3, 4, 4),
#'   role   = c("reference", "partner", "child", "reference", "child",
#'              "child", "reference", "reference")
#' )
#' ensure_counts(families, family, role,
#'               limits = list(reference = 1, partner = c(0, 1)))
#'
#' # At most two parents per child
#' parents <- data.frame(child = c("a", "a", "b", "b", "b"),
#'                       parent = c("m", "f", "m", "f", "x"))
#' ensure_counts(parents, child, limits = c(0, 2))
#'
#' @seealso [describe_groups()] to see the compositions first,
#'   [ensure_references()], [checkpoints].
#'
#' @export
ensure_counts <- function(data, group, role = NULL, limits,
                          success_msg = NULL,
                          warn_msg    = NULL,
                          abort_msg   = NULL) {
  tbl <- check_table(data)
  groups <- select_names(tbl, {{ group }})
  role_col <- select_names(tbl, {{ role }})
  if (length(groups) == 0) cli::cli_abort("{.arg group} must select at least one column.")
  if (length(role_col) > 1) cli::cli_abort("{.arg role} must select at most one column.")
  rules <- parse_limits(limits, has_role = length(role_col) == 1)
  broken_col <- diagnostic_name(tbl, "broken")

  rows <- if (is_remote(tbl)) {
    remote_counts(dplyr::ungroup(tbl), groups, role_col, rules, broken_col)
  } else {
    gid <- group_ids(data, groups)
    n_groups <- attr(gid, "n")
    counts <- if (length(role_col)) {
      x <- as.character(data[[role_col]])
      vapply(rules$role, function(r) tabulate(gid[which(x == r)], n_groups), numeric(n_groups))
    } else {
      matrix(tabulate(gid, n_groups), ncol = 1)
    }
    counts <- matrix(counts, nrow = n_groups)
    label <- character(n_groups)
    for (j in seq_len(nrow(rules))) {
      off <- counts[, j] < rules$min[j] | counts[, j] > rules$max[j]
      add <- paste0(rules$label[j], ": ", counts[off, j], " (", rules$needs[j], ")")
      label[off] <- ifelse(nzchar(label[off]), paste(label[off], add, sep = ", "), add)
    }
    hit <- which(nzchar(label[gid]))
    out <- tibble::as_tibble(data)[hit, ]
    out <- tibble::add_column(out, !!broken_col := label[gid[hit]], .before = 1)
    o <- do.call(order, c(unname(as.list(out[groups])), list(method = "radix", na.last = FALSE)))
    out[o, ]
  }

  what <- paste0(if (length(role_col)) paste0(role_col, " ") else "rows ", "per ", toString(groups))
  report_check(
    rows,
    pass = paste0("Within the limits: ", what),
    fail = paste0("Outside the limits: ", what),
    success_msg, warn_msg, abort_msg,
    key = c(groups, role_col, broken_col),
    show = character(),
    summary = function(v, n) {
      # Groups, not rows, per limit broken
      per_group <- dplyr::distinct(dplyr::ungroup(v), !!!rlang::syms(c(groups, broken_col)))
      tv <- top_values(per_group, broken_col)
      more <- tv$distinct - length(tv$n)
      c(paste0("In ", count(n_distinct_rows(v, groups), "group")),
        paste0(tv$value, " in ", count(tv$n, "group")),
        if (more > 0) paste0("... and ", count(more, "more combination")))
    }
  )
  invisible(data)
}

#' Assert that rows pointing to other rows find them, and agree
#'
#' A checkpoint for a column that points to another row of the same table:
#' a spouse's cpr, a mother's cpr, the reference person of a family. Each
#' reference must find its row, must not point to its own row, and with
#' `mutual = TRUE` the row it finds must point back, as spouses do. With
#' `same`, the row it finds must agree on those columns, such as the family
#' a spouse belongs to. The rows that break a rule are reported, with a
#' `problem` column saying which. Returns `data`, so it can sit in the
#' middle of a pipeline.
#'
#' In a panel a person has a row per year, and a reference should find the
#' row of the same year: give the period in `within`, and the row is looked
#' up among the rows with the same values there. `id` must be unique within
#' `within`; check it with [ensure_unique()] first. A missing reference is
#' no reference, and passes.
#'
#' Rules about the row a reference finds, such as a mother older than her
#' child, are written by joining its columns on and stating the rule with
#' [ensure_none()]:
#'
#' ```r
#' persons |>
#'   dplyr::left_join(dplyr::select(persons, mother = cpr, mother_born = born),
#'                    by = "mother") |>
#'   ensure_none(mother_born >= born)
#' ```
#'
#' @param id The column identifying each row (one column), e.g. `cpr`.
#' @param ref The column pointing to another row's `id` (one column), e.g.
#'   `spouse`.
#' @param within Columns the row pointed to must share to be found
#'   (tidy-select), e.g. `year`, or `NULL` (default).
#' @param same Columns the row pointed to must agree on once found
#'   (tidy-select), e.g. `family`, or `NULL` (default).
#' @param mutual If `TRUE`, the row pointed to must point back. Default
#'   `FALSE`.
#' @inheritParams describe_groups
#' @inheritParams checkpoints
#' @param warn_msg Message shown when a reference breaks a rule and no
#'   `abort_msg` is set. Defaults to a description of the check.
#'
#' @return `data` invisibly, unchanged.
#'
#' @examples
#' persons <- data.frame(
#'   cpr    = c("a", "b", "c", "d", "e"),
#'   spouse = c("b", "a", "d", "e", "x"),
#'   family = c(1, 1, 2, 3, 3)
#' )
#' # c points to d, who points to e; e points to x, who is not there; c and
#' # d are in different families
#' ensure_references(persons, cpr, spouse, same = family, mutual = TRUE)
#'
#' @seealso [ensure_matched()] for references to another table,
#'   [ensure_counts()], [checkpoints].
#'
#' @export
ensure_references <- function(data, id, ref, within = NULL, same = NULL, mutual = FALSE,
                              success_msg = NULL,
                              warn_msg    = NULL,
                              abort_msg   = NULL) {
  tbl <- dplyr::ungroup(check_table(data))
  id_col  <- select_names(tbl, {{ id }})
  ref_col <- select_names(tbl, {{ ref }})
  within_cols <- select_names(tbl, {{ within }})
  same_cols   <- select_names(tbl, {{ same }})
  if (length(id_col) != 1 || length(ref_col) != 1) {
    cli::cli_abort("{.arg id} and {.arg ref} must each select exactly one column.")
  }
  if (!rlang::is_bool(mutual)) cli::cli_abort("{.arg mutual} must be TRUE or FALSE.")
  if (length(intersect(c(id_col, ref_col), c(within_cols, same_cols)))) {
    cli::cli_abort("{.arg within} and {.arg same} must not hold {.arg id} or {.arg ref}.")
  }
  key <- c(id_col, within_cols)
  n_keys <- n_distinct_rows(dplyr::filter(tbl, !is.na(.data[[id_col]])), key)
  n_ided <- if (is_remote(tbl)) remote_nrow(dplyr::filter(tbl, !is.na(.data[[id_col]])))
            else sum(!is.na(tbl[[id_col]]))
  if (n_keys < n_ided) {
    cli::cli_abort(c(
      "{.arg id} is not unique{if (length(within_cols)) paste0(' within ', toString(within_cols)) else ''}, so a reference may find more than one row.",
      "i" = "Find the duplicates with {.code ensure_unique()} on {.val {key}}."
    ))
  }

  problem_col <- diagnostic_name(tbl, "problem")
  # The rows that can be pointed to, with their id, the `same` columns and
  # their own reference under names of their own (paste0() would give one
  # name for no `same` column)
  same_new <- if (length(same_cols)) paste0(".inshape_same", seq_along(same_cols)) else character()
  targets <- tbl |>
    dplyr::filter(!is.na(.data[[id_col]])) |>
    dplyr::select(dplyr::all_of(c(id_col, within_cols, same_cols, ref_col))) |>
    dplyr::rename(!!!stats::setNames(
      c(id_col, same_cols, ref_col),
      c(".inshape_id", same_new, ".inshape_back"))) |>
    dplyr::mutate(.inshape_found = 1L)

  tests <- list(
    rlang::expr(.data[[!!ref_col]] == .data[[!!id_col]] ~ "points to itself"),
    rlang::expr(is.na(.data$.inshape_found) ~ "not found")
  )
  for (k in seq_along(same_cols)) {
    s <- same_cols[k]
    other <- paste0(".inshape_same", k)
    tests <- c(tests, list(rlang::expr(
      (is.na(.data[[!!s]]) != is.na(.data[[!!other]])) | .data[[!!s]] != .data[[!!other]] ~
        !!paste("in another", s))))
  }
  if (mutual) {
    tests <- c(tests, list(rlang::expr(
      is.na(.data$.inshape_back) | .data$.inshape_back != .data[[!!id_col]] ~ "does not point back")))
  }

  joined <- tbl |>
    dplyr::filter(!is.na(.data[[ref_col]])) |>
    dplyr::left_join(targets, by = c(stats::setNames(".inshape_id", ref_col),
                                     stats::setNames(within_cols, within_cols)),
                     na_matches = "na") |>
    dplyr::mutate(!!problem_col := dplyr::case_when(!!!tests, .default = NA_character_)) |>
    dplyr::filter(!is.na(.data[[problem_col]])) |>
    dplyr::select(!dplyr::starts_with(".inshape_")) |>
    dplyr::relocate(dplyr::all_of(problem_col))
  rows <- if (is_remote(joined)) sort_by(joined, na_first(c(id_col, within_cols))) else joined

  report_check(
    rows,
    pass = paste0("References found", if (mutual) " and mutual", ": ", ref_col, " to ", id_col),
    fail = paste0("Broken references: ", ref_col, " to ", id_col),
    success_msg, warn_msg, abort_msg,
    key = c(id_col, ref_col, within_cols, same_cols),
    group = problem_col,
    show = character(),
    summary = function(v, n) tally_line("Problems", top_values(v, problem_col))
  )
  invisible(data)
}

# Limits as a table: role (or NA), min, max, the label in messages and
# what is needed, e.g. "needs 1", "needs at most 2"
parse_limits <- function(limits, has_role, call = rlang::caller_env()) {
  if (missing(limits)) cli::cli_abort("Give the {.arg limits}.", call = call)
  one <- function(x, what) {
    if (!is.numeric(x) || !length(x) %in% 1:2 || anyNA(x) || any(x < 0) ||
        (length(x) == 2 && x[1] > x[2])) {
      cli::cli_abort("The limit for {what} must be a count, or the least and the most as two numbers.",
                     call = call)
    }
    range(x)
  }
  if (has_role) {
    if (!is.list(limits) || is.null(names(limits)) || any(!nzchar(names(limits)))) {
      cli::cli_abort("With {.arg role}, {.arg limits} must be a named list, such as {.code list(reference = 1)}.",
                     call = call)
    }
    r <- lapply(names(limits), function(nm) one(limits[[nm]], nm))
    roles <- names(limits)
  } else {
    if (is.list(limits)) {
      cli::cli_abort("Without {.arg role}, {.arg limits} is one count or range of rows per group.",
                     call = call)
    }
    r <- list(one(limits, "rows"))
    roles <- NA_character_
  }
  lo <- vapply(r, `[`, numeric(1), 1)
  hi <- vapply(r, `[`, numeric(1), 2)
  needs <- ifelse(lo == hi, paste("needs", lo),
           ifelse(is.infinite(hi), paste("needs at least", lo),
           ifelse(lo == 0, paste("needs at most", hi), paste("needs", lo, "to", hi))))
  tibble::tibble(role = roles, min = lo, max = hi,
                 label = ifelse(is.na(roles), "rows", roles), needs = needs)
}

# The same counts per group in a query, the broken limits named in SQL,
# and the rows of the groups that break one
remote_counts <- function(tbl, groups, role_col, rules, broken_col) {
  con <- dbplyr::remote_con(tbl)
  sums <- if (length(role_col)) {
    proto <- table_prototype(tbl)[[role_col]]
    values <- typed_values(rules$role, proto)
    lapply(values, function(v) {
      rlang::expr(sum(dplyr::if_else(.data[[!!role_col]] == !!v, 1L, 0L), na.rm = TRUE))
    })
  } else {
    list(rlang::expr(dplyr::n()))
  }
  cols <- paste0(".inshape_c", seq_along(sums))
  names(sums) <- cols
  q <- function(x) DBI::dbQuoteIdentifier(con, x)
  s <- function(x) DBI::dbQuoteString(con, x)
  parts <- vapply(seq_len(nrow(rules)), function(j) {
    test <- paste0(q(cols[j]), " < ", rules$min[j],
                   if (is.finite(rules$max[j])) paste0(" OR ", q(cols[j]), " > ", rules$max[j]))
    paste0("CASE WHEN ", test, " THEN CONCAT(", s(paste0(rules$label[j], ": ")), ", CAST(",
           q(cols[j]), " AS VARCHAR), ", s(paste0(" (", rules$needs[j], ")")), ") END")
  }, character(1))
  per_group <- tbl |>
    dplyr::group_by(!!!rlang::syms(groups)) |>
    dplyr::summarise(!!!sums, .groups = "drop") |>
    dplyr::mutate(!!broken_col := !!dbplyr::sql(paste0("CONCAT_WS(', ', ", paste(parts, collapse = ", "), ")"))) |>
    dplyr::filter(.data[[broken_col]] != "") |>
    dplyr::select(dplyr::all_of(c(groups, broken_col)))
  tbl |>
    dplyr::inner_join(per_group, by = groups, na_matches = "na") |>
    dplyr::relocate(dplyr::all_of(broken_col)) |>
    sort_by(na_first(groups))
}

# Rows per group (rows of the matrix) and role (columns)
role_matrix <- function(gid, rid, n_roles) {
  n_groups <- attr(gid, "n")
  m <- matrix(tabulate((rid - 1L) * n_groups + gid, n_groups * n_roles), nrow = n_groups)
  colnames(m) <- paste0("r", seq_len(n_roles))
  m[tabulate(gid, n_groups) > 0L, , drop = FALSE]
}

remote_role_counts <- function(tbl, groups, role_col, roles) {
  exprs <- lapply(roles, function(v) {
    if (is.na(v)) rlang::expr(sum(dplyr::if_else(is.na(.data[[!!role_col]]), 1L, 0L), na.rm = TRUE))
    else rlang::expr(sum(dplyr::if_else(.data[[!!role_col]] == !!v, 1L, 0L), na.rm = TRUE))
  })
  names(exprs) <- paste0(".inshape_r", seq_along(roles))
  list(exprs = exprs,
       query = dplyr::summarise(dplyr::group_by(tbl, !!!rlang::syms(groups)), !!!exprs, .groups = "drop"))
}

check_role_count <- function(roles, call = rlang::caller_env()) {
  if (length(roles) > 30) {
    cli::cli_abort(c("{.arg role} has {length(roles)} values; a composition needs a few roles.",
                     "i" = "Group the roles into fewer first, such as adult and child."),
                   call = call)
  }
}

# "1 reference + 1 partner + 2 child", roles with a count of 0 left out
composition_text <- function(counts, labels) {
  n <- length(counts[[1]])
  out <- character(n)
  for (j in seq_along(labels)) {
    c_j <- counts[[j]]
    add <- ifelse(c_j > 0, paste(c_j, labels[j]), "")
    out <- ifelse(nzchar(add), ifelse(nzchar(out), paste(out, add, sep = " + "), add), out)
  }
  out[!nzchar(out)] <- "none"
  out
}
