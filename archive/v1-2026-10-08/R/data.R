# Data acquisition and training-only preprocessing.
adult_columns <- c("age", "workclass", "fnlwgt", "education", "educationnum",
  "maritalstatus", "occupation", "relationship", "race", "sex", "capitalgain",
  "capitalloss", "hoursperweek", "nativecountry", "incomelevel")
income_levels <- c("<=50K", ">50K")
numeric_columns <- c("age", "fnlwgt", "educationnum", "capitalgain", "capitalloss", "hoursperweek")
predictor_columns <- setdiff(adult_columns, c("incomelevel", "education", "fnlwgt"))
adult_checksums <- c(adult.data = "5d7c39d7b8804f071cdd1f2a7c460872",
  adult.test = "35238206dfdf7f1fe215bbb874adecdc", adult.names = "1a7cdb3ff7a1b709968b1c7a11def63e")
adult_base_url <- "https://archive.ics.uci.edu/ml/machine-learning-databases/adult/"

download_adult <- function(directory) {
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  for (name in names(adult_checksums)) {
    path <- file.path(directory, name)
    if (!file.exists(path)) {
      temporary <- tempfile(pattern = paste0(name, "-"), tmpdir = directory)
      tryCatch({
        utils::download.file(paste0(adult_base_url, name), temporary, mode = "wb", quiet = TRUE)
        if (unname(tools::md5sum(temporary)) != adult_checksums[[name]])
          stop("Downloaded input does not match the recorded UCI checksum: ", name)
        if (!file.rename(temporary, path)) stop("Cannot save downloaded input: ", path)
      }, finally = unlink(temporary))
    }
    if (unname(tools::md5sum(path)) != adult_checksums[[name]])
      stop("Existing input differs from the recorded UCI source: ", path,
        ". Preserve it separately before downloading the reference data.")
  }
  invisible(directory)
}

read_adult <- function(path, prefix) {
  if (!file.exists(path)) stop("Missing data file: ", path, ". Run with --download first.")
  lines <- trimws(readLines(path, warn = FALSE))
  lines <- lines[nzchar(lines) & !startsWith(lines, "|")]
  if (!length(lines)) stop("Empty Adult data file: ", path)
  fields <- strsplit(lines, ",", fixed = TRUE)
  if (any(lengths(fields) != length(adult_columns))) stop("Adult input must have exactly 15 columns: ", path)
  raw <- as.data.frame(do.call(rbind, lapply(fields, trimws)), stringsAsFactors = FALSE)
  names(raw) <- adult_columns
  raw[raw == "?" | raw == ""] <- NA_character_
  raw$incomelevel <- sub("\\.$", "", raw$incomelevel)
  if (anyNA(raw$incomelevel) || any(!raw$incomelevel %in% income_levels))
    stop("Income labels must be <=50K or >50K (an optional final period is allowed).")
  for (name in numeric_columns) {
    value <- suppressWarnings(as.numeric(raw[[name]]))
    if (any(!is.na(raw[[name]]) & (is.na(value) | !is.finite(value))))
      stop("Invalid numeric input in ", name, ": ", path)
    if (any(value < 0, na.rm = TRUE)) stop("Negative numeric input in ", name)
    raw[[name]] <- value
  }
  raw$incomelevel <- factor(raw$incomelevel, levels = income_levels)
  raw$row_id <- sprintf("%s:%05d", prefix, seq_len(nrow(raw)))
  raw
}

predictor_signature <- function(data) {
  columns <- setdiff(adult_columns, "incomelevel")
  do.call(paste, c(lapply(data[columns], function(x) {
    x <- as.character(x); x[is.na(x)] <- "<NA>"; x
  }), sep = "\034"))
}

prepare_partitions <- function(train, test) {
  train_key <- predictor_signature(train)
  test_key <- predictor_signature(test)
  counts <- tapply(as.character(train$incomelevel), train_key, function(x) length(unique(x)))
  conflicts <- names(counts)[counts > 1L]
  conflict_rows <- train_key %in% conflicts
  keep_train <- !conflict_rows & !duplicated(train_key)
  # Membership never inspects the test outcome.
  overlap <- test_key %in% train_key
  audit <- data.frame(item = c("raw_training_rows", "raw_test_rows", "training_conflicting_signatures",
    "training_conflict_rows_excluded", "training_duplicate_rows_excluded",
    "test_train_overlap_rows_excluded", "test_internal_duplicate_rows_retained",
    "eligible_training_rows", "eligible_test_rows", "training_rows_with_missing_values",
    "test_rows_with_missing_values"), value = c(nrow(train), nrow(test), length(conflicts),
    sum(conflict_rows), sum(!conflict_rows & duplicated(train_key)), sum(overlap),
    sum(duplicated(test_key[!overlap])), sum(keep_train), sum(!overlap),
    sum(!complete.cases(train[adult_columns])), sum(!complete.cases(test[adult_columns]))))
  list(train = train[keep_train, , drop = FALSE], test = test[!overlap, , drop = FALSE], audit = audit)
}

stratified_indices <- function(y, fraction, seed) {
  if (length(fraction) != 1L || !is.finite(fraction) || fraction <= 0 || fraction >= 1)
    stop("Stratified split fraction must lie strictly between zero and one.")
  if (anyNA(y) || !all(income_levels %in% as.character(y))) stop("Both income classes are required.")
  set.seed(seed)
  index <- unlist(lapply(income_levels, function(level) {
    available <- which(y == level)
    if (length(available) < 2L) stop("Each income class requires at least two rows.")
    count <- min(length(available) - 1L, max(1L, floor(length(available) * fraction)))
    available[sample.int(length(available), count)]
  }), use.names = FALSE)
  sort(index)
}

stratified_limit <- function(data, maximum, seed) {
  if (nrow(data) <= maximum) return(data)
  index <- stratified_indices(data$incomelevel, maximum / nrow(data), seed)
  data[index, , drop = FALSE]
}

fit_preprocessor <- function(data) {
  if (!all(predictor_columns %in% names(data))) stop("Missing predictor columns.")
  numerics <- intersect(numeric_columns, predictor_columns)
  categoricals <- setdiff(predictor_columns, numerics)
  numeric_spec <- lapply(data[numerics], function(x) {
    if (all(is.na(x))) stop("A numeric training column has no observed values.")
    median_value <- stats::median(x, na.rm = TRUE)
    x[is.na(x)] <- median_value
    deviation <- stats::sd(x)
    if (!is.finite(deviation) || deviation == 0) deviation <- 1
    list(median = median_value, center = mean(x), scale = deviation)
  })
  categorical_spec <- lapply(data[categoricals], function(x) {
    x <- as.character(x); x[is.na(x)] <- "__MISSING__"
    counts <- table(x)
    mode <- names(counts)[which.max(counts)]
    list(levels = c(mode, sort(setdiff(unique(x), mode))), mode = mode)
  })
  specification <- list(numeric = numeric_spec, categorical = categorical_spec, columns = NULL)
  matrix <- apply_preprocessor(specification, data)
  variable <- vapply(seq_len(ncol(matrix)), function(j) length(unique(matrix[, j])) > 1L, logical(1))
  specification$columns <- colnames(matrix)[variable]
  if (!length(specification$columns)) stop("Training predictors contain no variation.")
  specification
}

apply_preprocessor <- function(specification, data) {
  if (!all(predictor_columns %in% names(data))) stop("Missing predictor columns.")
  blocks <- list()
  for (name in names(specification$numeric)) {
    spec <- specification$numeric[[name]]
    value <- data[[name]]; value[is.na(value)] <- spec$median
    blocks[[name]] <- matrix((value - spec$center) / spec$scale, ncol = 1L,
      dimnames = list(NULL, name))
  }
  for (name in names(specification$categorical)) {
    spec <- specification$categorical[[name]]
    value <- as.character(data[[name]]); value[is.na(value)] <- "__MISSING__"
    value[!value %in% spec$levels] <- spec$mode
    if (length(spec$levels) > 1L) {
      block <- vapply(spec$levels[-1L], function(level) as.numeric(value == level), numeric(nrow(data)))
      block <- matrix(block, nrow = nrow(data), ncol = length(spec$levels) - 1L)
      colnames(block) <- paste(name, spec$levels[-1L], sep = "_")
      blocks[[name]] <- block
    }
  }
  matrix <- do.call(cbind, blocks)
  colnames(matrix) <- make.names(colnames(matrix), unique = TRUE)
  if (!is.null(specification$columns)) matrix <- matrix[, specification$columns, drop = FALSE]
  storage.mode(matrix) <- "double"
  if (any(!is.finite(matrix))) stop("Preprocessing produced non-finite predictors.")
  matrix
}

unseen_categories <- function(specification, data, partition) {
  do.call(rbind, lapply(names(specification$categorical), function(name) {
    value <- as.character(data[[name]]); value[is.na(value)] <- "__MISSING__"
    data.frame(partition = partition, feature = name,
      unseen_rows = sum(!value %in% specification$categorical[[name]]$levels))
  }))
}
