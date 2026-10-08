# Offline methodology-v2 regression checks. Run: Rscript --vanilla tests/run_tests.R
invocation <- grep("^--file=", commandArgs(FALSE), value = TRUE)
root <- if (length(invocation)) dirname(dirname(normalizePath(sub("^--file=", "", invocation[1L])))) else getwd()
if (dir.exists(file.path(root, ".R-library"))) .libPaths(c(file.path(root, ".R-library"), .libPaths()))
module_files <- c("data.R", "models.R", "evaluation.R", "plots.R", "reporting.R", "pipeline.R")
module_files <- module_files[file.exists(file.path(root, "R", module_files))]
for (file in module_files) source(file.path(root, "R", file))
source(file.path(root, "scripts", "export_evidence.R"))

run_income_tests <- function() {
  passed <- 0L; failures <- character()
  fixture_root <- tempfile("income-v2-tests-", tmpdir = tempdir())
  stopifnot(dir.create(fixture_root))
  on.exit({
    resolved <- normalizePath(fixture_root, winslash = "/", mustWork = TRUE)
    temporary <- normalizePath(tempdir(), winslash = "/", mustWork = TRUE)
    if (identical(dirname(resolved), temporary) && startsWith(basename(resolved), "income-v2-tests-"))
      unlink(resolved, recursive = TRUE)
  }, add = TRUE)
  original_kind <- RNGkind()
  had_seed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  if (had_seed) original_seed <- .Random.seed
  on.exit({
    do.call(RNGkind, as.list(original_kind))
    if (had_seed) assign(".Random.seed", original_seed, envir = .GlobalEnv)
    else if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) rm(".Random.seed", envir = .GlobalEnv)
  }, add = TRUE)
  check <- function(name, code) tryCatch({
    force(code); passed <<- passed + 1L; cat("PASS ", name, "\n", sep = "")
  }, error = function(e) {
    failures <<- c(failures, paste0(name, ": ", conditionMessage(e)))
    cat("FAIL ", name, ": ", conditionMessage(e), "\n", sep = "")
  })
  expect_error <- function(code, pattern = NULL) {
    error <- tryCatch({ force(code); NULL }, error = identity)
    if (!inherits(error, "error")) stop("Expected an error.")
    if (!is.null(pattern) && !grepl(pattern, conditionMessage(error), ignore.case = TRUE))
      stop("Unexpected error: ", conditionMessage(error))
    invisible(error)
  }
  equal <- function(actual, expected, tolerance = 1e-10) {
    value <- all.equal(actual, expected, tolerance = tolerance, check.attributes = FALSE)
    if (!isTRUE(value)) stop(paste(value, collapse = "; "))
  }
  fixture_file <- function(lines) {
    path <- tempfile("input-", tmpdir = fixture_root)
    writeLines(lines, path); path
  }
  fixture_dir <- function() {
    path <- tempfile("run-", tmpdir = fixture_root)
    stopifnot(dir.create(path)); path
  }
  synthetic_adult <- function(n = 240L, seed = 901L, prefix = "synthetic") with_income_rng(seed, {
    data <- data.frame(age = sample(20:70, n, TRUE),
      workclass = sample(c("Private", "Self-emp-not-inc", "State-gov"), n, TRUE),
      fnlwgt = 100000 + seq_len(n), education = sample(c("Bachelors", "HS-grad", "Masters"), n, TRUE),
      educationnum = sample(8:16, n, TRUE),
      maritalstatus = sample(c("Never-married", "Married-civ-spouse", "Divorced"), n, TRUE),
      occupation = sample(c("Adm-clerical", "Craft-repair", "Exec-managerial"), n, TRUE),
      relationship = sample(c("Not-in-family", "Husband", "Wife"), n, TRUE),
      race = sample(c("White", "Black", "Asian-Pac-Islander"), n, TRUE),
      sex = sample(c("Female", "Male"), n, TRUE), capitalgain = sample(c(0, 500, 2500), n, TRUE),
      capitalloss = sample(c(0, 200), n, TRUE), hoursperweek = sample(20:60, n, TRUE),
      nativecountry = sample(c("United-States", "Canada", "Mexico"), n, TRUE), stringsAsFactors = FALSE)
    probability <- plogis(-0.4 + 0.035 * (data$age - 40) + 0.18 * (data$educationnum - 11))
    data$incomelevel <- factor(ifelse(runif(n) < probability, ">50K", "<=50K"), levels = income_levels)
    data$row_id <- sprintf("%s:%05d", prefix, seq_len(n)); data
  })
  raw_lines <- function(data) apply(data[adult_columns], 1L, function(row) paste(ifelse(is.na(row), "?", row), collapse = ", "))
  kinds <- c("majority", "logistic", "tree", "forest", "svm")
  plots <- c("model_comparison", "roc_pr_curves", "confusion_matrices", "calibration", "subgroup_recall", "cv_comparison")
  allowlist <- c("report.md", "metrics.csv", "cv_metrics.csv", "cv_summary.csv", "selected_parameters.csv",
    "diagnostics.csv", "subgroup_metrics.csv", "metric_intervals.csv", "paired_differences.csv", "bootstrap_design.csv", "calibration.csv",
    "profile_overlap.csv", "profile_sensitivity.csv", "data_audit.csv", "input_manifest.csv", "source_manifest.csv",
    "package_versions.csv", "run_config.txt", "warnings.txt", "unseen_categories.csv", "methodology.md",
    paste0(plots, ".png"), paste0(plots, ".pdf"))
  private <- c("predictions.csv", "oof_predictions.csv", "fold_assignments.csv", "split_assignments.csv", "models.rds", "session_info.txt")
  refresh_manifest <- function(directory) {
    paths <- list.files(directory, full.names = TRUE)
    paths <- paths[basename(paths) != "artifact_manifest.csv"]
    write.csv(data.frame(file = basename(paths), bytes = file.info(paths)$size,
      md5 = unname(tools::md5sum(paths))), file.path(directory, "artifact_manifest.csv"), row.names = FALSE)
  }
  export_fixture <- function() {
    directory <- fixture_dir()
    for (file in c(allowlist, private)) writeLines(paste("Synthetic exporter fixture:", file), file.path(directory, file))
    writeLines(c("mode: full", "methodology_version: 2", "status: complete"), file.path(directory, "run_config.txt"))
    write.csv(data.frame(file = c("adult.data", "adult.test"), md5 = unname(adult_checksums[1:2]),
      matches_uci_reference = TRUE), file.path(directory, "input_manifest.csv"), row.names = FALSE)
    write.csv(data.frame(model = kinds, stage = "final", fit_ok = TRUE,
      converged = c(NA, TRUE, NA, NA, NA), solver_status = c(NA, 0, NA, NA, NA),
      finite_parameters = c(NA, TRUE, NA, NA, NA), n_training = 240L, n_features = 20L),
      file.path(directory, "diagnostics.csv"), row.names = FALSE)
    refresh_manifest(directory); directory
  }

  check("Parser handles UCI formatting and rejects malformed input", {
    data <- synthetic_adult(4L); data$workclass[2] <- NA; data$age[2] <- NA
    lines <- raw_lines(data); lines[3] <- paste0(lines[3], ".")
    parsed <- read_adult(fixture_file(c("| test header", "", lines)), "fixture")
    stopifnot(nrow(parsed) == 4L, is.na(parsed$workclass[2]), is.na(parsed$age[2]),
      identical(levels(parsed$incomelevel), income_levels))
    equal(as.character(parsed$incomelevel), as.character(data$incomelevel))
    expect_error(read_adult(fixture_file(""), "bad"), "Empty")
    expect_error(read_adult(fixture_file("1,2,3"), "bad"), "15 columns")
    for (value in c("Inf", "NaN", "-1", "forty")) {
      changed <- data; changed$age <- value
      expect_error(read_adult(fixture_file(raw_lines(changed)), "bad"), "numeric")
    }
    changed <- data; changed$incomelevel <- "bad"
    expect_error(read_adult(fixture_file(raw_lines(changed)), "bad"), "Income labels")
  })
  check("Duplicate policy retains conflicting outcomes and excludes raw train overlaps without test labels", {
    core <- synthetic_adult(5L)
    train <- core[c(1,1,2,2,3), ]; train$row_id <- paste0("train:",1:5)
    train$incomelevel <- factor(c("<=50K","<=50K","<=50K",">50K",">50K"), levels = income_levels)
    test <- core[c(1,2,4,4,5), ]; test$row_id <- paste0("test:",1:5)
    result <- prepare_partitions(train,test)
    equal(result$train$row_id, c("train:1","train:3","train:4","train:5"))
    equal(result$test$row_id, c("test:3","test:4","test:5"))
    audit <- setNames(result$audit$value,result$audit$item)
    stopifnot(audit[["training_conflict_rows_retained"]] == 2L,
      audit[["training_duplicate_rows_excluded"]] == 1L, audit[["test_internal_duplicate_rows_retained"]] == 1L)
    test$incomelevel <- factor(ifelse(test$incomelevel == ">50K","<=50K",">50K"),levels=income_levels)
    changed <- prepare_partitions(train,test)
    equal(result$train,changed$train); equal(result$test$row_id,changed$test$row_id); equal(result$audit,changed$audit)
    one <- core[1,]; another <- one; another$fnlwgt <- another$fnlwgt + 1
    stopifnot(predictor_signature(one) != predictor_signature(another),
      model_input_signature(one) == model_input_signature(another))
  })
  check("Grouped folds keep identical predictors together and reproduce across caller RNG settings", {
    data <- synthetic_adult(); pair <- data[1, ]; pair$incomelevel <- factor(ifelse(pair$incomelevel==">50K","<=50K",">50K"),levels=income_levels)
    data <- rbind(data,pair); data$row_id <- paste0("group:",seq_len(nrow(data)))
    RNGkind("Mersenne-Twister","Inversion","Rejection"); set.seed(91); saved <- .Random.seed
    first <- stratified_group_folds(data,5L,12345L)
    stopifnot(identical(saved,.Random.seed), first[1] == tail(first,1))
    RNGkind("L'Ecuyer-CMRG","Inversion","Rejection"); set.seed(21); saved <- .Random.seed; kind <- RNGkind()
    second <- stratified_group_folds(data,5L,12345L)
    equal(first,second); stopifnot(identical(saved,.Random.seed),identical(kind,RNGkind()))
    for(fold in 1:5) stopifnot(all(table(data$incomelevel[first==fold])>0),
      !any(predictor_signature(data[first==fold,]) %in% predictor_signature(data[first!=fold,])))
    expect_error(stratified_group_folds(data,1L,12345L),"fold")
    expect_error(stratified_group_folds(data,500L,12345L),"enough")
  })
  check("Fold preprocessing learns only supplied rows and log-transforms monetary inputs", {
    train <- synthetic_adult(12L); train$age[3] <- NA
    train$educationnum <- 10; train$workclass <- rep(c("Private","State-gov",NA),4)
    spec <- fit_preprocessor(train); x <- apply_preprocessor(spec,train)
    equal(spec$numeric$age$median,median(train$age,na.rm=TRUE))
    equal(spec$numeric$capitalgain$center,mean(log1p(train$capitalgain)))
    stopifnot(!"educationnum" %in% colnames(x), !any(grepl("^fnlwgt|^education_",colnames(x))))
    holdout <- train[1:2,]; holdout$age <- c(10000,NA); holdout$workclass <- c("UNSEEN","Private")
    frozen <- serialize(spec,NULL); scored <- apply_preprocessor(spec,holdout)
    equal(scored[1,"age"],(10000-spec$numeric$age$center)/spec$numeric$age$scale)
    stopifnot(identical(frozen,serialize(spec,NULL)),identical(colnames(x),colnames(scored)),all(is.finite(scored)))
    changed <- train; changed$incomelevel <- factor(rev(as.character(train$incomelevel)),levels=income_levels)
    changed$fnlwgt <- 7; changed$education <- "ignored"
    equal(fit_preprocessor(changed),spec)
    train$age <- NA_real_; expect_error(fit_preprocessor(train),"observed")
  })
  check("Confusion metrics, ties-aware ROC and average precision match analytic answers", {
    truth <- factor(c("<=50K",">50K","<=50K",">50K"),levels=income_levels)
    prediction <- factor(c("<=50K","<=50K",">50K",">50K"),levels=income_levels)
    result <- income_metrics(truth,prediction,c(.1,.2,.2,.9))
    for (name in c("accuracy","balanced_accuracy","precision","recall","specificity","f1")) equal(result[[name]],.5)
    equal(result$roc_auc,.875); equal(result$average_precision,5/6)
    equal(average_precision(truth,rep(.5,4)),.5)
    points <- roc_points(truth,c(.1,.2,.2,.9))
    equal(sum(diff(points$fpr)*(head(points$tpr,-1)+tail(points$tpr,-1))/2),result$roc_auc)
    negative <- factor(rep("<=50K",4),levels=income_levels)
    undefined <- income_metrics(negative,negative,rep(0,4))
    stopifnot(is.na(undefined$roc_auc),is.na(undefined$balanced_accuracy),is.na(undefined$recall))
    expect_error(income_metrics(truth,prediction,c(NA,.2,.2,.9)),"finite")
  })
  check("ROC AUC remains valid beyond integer pair-count range", {
    truth <- factor(rep(income_levels,each=50000L),levels=income_levels)
    result <- income_metrics(truth,truth,c(rep(0,50000),rep(1,50000)))
    equal(result$roc_auc,1); equal(result$average_precision,1)
  })
  check("CSV preserves adjacent double scores, missing values, and tied-score average precision", {
    scores <- c(.1, .39491679675822894, .39491679675822888, .7)
    truth <- factor(c("<=50K",">50K",">50K","<=50K"),levels=income_levels)
    data <- data.frame(score=scores, missing=c(NA_real_,1/3,0,NA_real_),
      integer=1:4, text=c("comma,value", "quoted\"value", "plain", "end"))
    path <- tempfile("roundtrip-",tmpdir=fixture_root,fileext=".csv")
    write_income_csv(data,path)
    restored <- read.csv(path,stringsAsFactors=FALSE)
    stopifnot(identical(restored$score,scores),identical(restored$missing,data$missing),
      identical(restored$integer,data$integer),identical(restored$text,data$text),
      length(unique(restored$score))==4L)
    equal(average_precision(truth,restored$score),average_precision(truth,scores),tolerance=0)
  })
  check("Probability metrics and calibration exclude margins and expose clipping", {
    truth <- factor(c("<=50K",">50K"),levels=income_levels)
    perfect <- probability_metrics(truth,c(0,1))
    equal(perfect$brier_score,0); stopifnot(is.finite(perfect$log_loss),perfect$probability_clipped_n==2L)
    half <- probability_metrics(truth,c(.5,.5)); equal(half$brier_score,.25); equal(half$log_loss,log(2))
    expect_error(probability_metrics(truth,c(-1,1)),"probab")
    p <- data.frame(row_id=c("a","b","a","b"),model=c("logistic","logistic","svm","svm"),
      truth=rep(truth,2),prediction=rep(truth,2),score=c(.25,.75,-2,2),score_type=c("probability","probability","decision_margin","decision_margin"))
    bins <- calibration_table(p)
    stopifnot(all(bins$model=="logistic"),sum(bins$n)==2L,all(bins$lower<=bins$upper))
  })
  check("All model families preserve schema, support one row, and pin/restore RNG", {
    data <- synthetic_adult(); x <- apply_preprocessor(fit_preprocessor(data),data)
    for(kind in kinds) {
      RNGkind("Mersenne-Twister","Inversion","Rejection"); set.seed(99); saved <- .Random.seed
      model <- fit_income_model(kind,x,data$incomelevel,trees=10L,seed=42L)
      stopifnot(identical(saved,.Random.seed),isTRUE(model$fit_ok))
      result <- predict_income_model(model,x)
      RNGkind("L'Ecuyer-CMRG","Inversion","Rejection"); set.seed(87); saved <- .Random.seed; rng <- RNGkind()
      again <- fit_income_model(kind,x,data$incomelevel,trees=10L,seed=42L)
      equal(result,predict_income_model(again,x)); stopifnot(identical(saved,.Random.seed),identical(rng,RNGkind()))
      stopifnot(length(predict_income_model(model,x[1,,drop=FALSE])$score)==1L)
      expect_error(predict_income_model(model,x[,rev(seq_len(ncol(x))),drop=FALSE]),"columns")
      if(kind=="logistic") stopifnot(model$converged,all(is.finite(model$coefficients)),model$model$jerr==0)
    }
    expect_error(fit_income_model("logistic",x,data$incomelevel,parameter=0),"lambda")
    expect_error(fit_income_model("forest",x,data$incomelevel,parameter=ncol(x)+1),"mtry")
    expect_error(fit_income_model("svm",x,data$incomelevel,parameter=0),"cost")
  })
  check("SVM margins orient correctly for either class ordering", {
    x <- cbind(signal=c(-3,-2,-1,1,2,3),other=c(0,1,0,0,1,0))
    truth <- factor(rep(income_levels,each=3),levels=income_levels)
    for(first in income_levels) {
      order <- c(which(truth==first),which(truth!=first))
      model <- fit_income_model("svm",x[order,],truth[order]); p <- predict_income_model(model,x)
      equal(as.character(p$class),as.character(truth)); equal(income_metrics(truth,p$class,p$score)$roc_auc,1)
    }
  })
  check("Saved models predict in a fresh R process without fitting or manually loading backends", {
    data <- synthetic_adult(120L,119L,"saved")
    x <- apply_preprocessor(fit_preprocessor(data),data)
    models <- setNames(lapply(kinds,function(kind)
      fit_income_model(kind,x,data$incomelevel,trees=10L,seed=32L)),kinds)
    expected <- lapply(models,predict_income_model,x=x)
    model_path <- tempfile("saved-models-",tmpdir=fixture_root,fileext=".rds")
    matrix_path <- tempfile("saved-matrix-",tmpdir=fixture_root,fileext=".rds")
    expected_path <- tempfile("saved-predictions-",tmpdir=fixture_root,fileext=".rds")
    script_path <- tempfile("fresh-inference-",tmpdir=fixture_root,fileext=".R")
    saveRDS(models,model_path); saveRDS(x,matrix_path); saveRDS(expected,expected_path)
    writeLines(c(
      "args <- commandArgs(trailingOnly=TRUE)",
      ".libPaths(c(file.path(args[1], '.R-library'), .libPaths()))",
      "source(file.path(args[1], 'R', 'data.R'))",
      "source(file.path(args[1], 'R', 'models.R'))",
      "stopifnot(!any(c('glmnet','rpart','ranger','e1071') %in% loadedNamespaces()))",
      "models <- readRDS(args[2]); x <- readRDS(args[3]); expected <- readRDS(args[4])",
      "for (kind in names(models)) {",
      "  actual <- predict_income_model(models[[kind]], x)",
      "  stopifnot(isTRUE(all.equal(actual, expected[[kind]], tolerance=1e-12)))",
      "}",
      "cat('Saved-model inference passed for all five families.\\n')"),script_path)
    executable <- file.path(R.home("bin"),if(.Platform$OS.type=="windows") "Rscript.exe" else "Rscript")
    output <- suppressWarnings(system2(executable,c("--vanilla",shQuote(script_path),shQuote(root),
      shQuote(model_path),shQuote(matrix_path),shQuote(expected_path)),stdout=TRUE,stderr=TRUE))
    status <- attr(output,"status")
    if(!is.null(status) && status != 0L) stop(paste(output,collapse="\n"))
    stopifnot(any(grepl("Saved-model inference passed",output,fixed=TRUE)))
  })
  check("Cluster bootstrap is deterministic, paired, and agrees with unweighted metrics", {
    truth <- factor(c("<=50K",">50K","<=50K",">50K","<=50K",">50K"),levels=income_levels)
    scores <- c(.1,.8,.4,.3,.2,.9)
    one <- data.frame(row_id=paste0("r",1:6),model="logistic",truth=truth,
      prediction=factor(ifelse(scores>.5,">50K","<=50K"),levels=income_levels),score=scores,score_type="probability")
    two <- one; two$model <- "forest"; predictions <- rbind(one,two)
    weighted <- weighted_income_metrics(prepare_weighted_metric(one),rep(1,6))
    direct <- income_metrics(one$truth,one$prediction,one$score)
    for(name in intersect(names(weighted),names(direct))) equal(weighted[[name]],direct[[name]])
    multiplicity <- c(0,3,2,1,0,2)
    repeated <- one[rep(seq_len(nrow(one)),multiplicity),,drop=FALSE]
    weighted <- weighted_income_metrics(prepare_weighted_metric(one),multiplicity)
    direct <- income_metrics(repeated$truth,repeated$prediction,repeated$score)
    for(name in intersect(names(weighted),names(direct))) equal(weighted[[name]],direct[[name]])
    result <- bootstrap_income_metrics(predictions,c("a","a","b","b","c","c"),reps=30L,seed=23L)
    again <- bootstrap_income_metrics(predictions,c("a","a","b","b","c","c"),reps=30L,seed=23L)
    equal(result,again)
    stopifnot(nrow(result$paired_differences)>0L,all(result$paired_differences$estimate==0),
      all(result$paired_differences$lower==0),all(result$paired_differences$upper==0),
      all(result$metric_intervals$valid_replicates==30L),result$bootstrap_design$n_clusters==3L)
    predictions$row_id[7:12] <- rev(predictions$row_id[7:12])
    expect_error(bootstrap_income_metrics(predictions,letters[1:6],reps=10L,seed=1L),"align|order|row")
  })
  check("CLI rejects obsolete/invalid settings and protects prior output", {
    options <- parse_options(c("--seed","23","--trees","10","--folds","3","--bootstrap","20","--smoke"),root)
    stopifnot(options$seed==23,options$trees==10,options$folds==3,options$bootstrap==20,options$smoke)
    for(pair in list(c("--folds","1"),c("--bootstrap","1"),c("--seed","-1"),c("--trees","0"),c("--validation-fraction",".2")))
      expect_error(parse_options(pair,root))
    options$output <- fixture_file("preserve")
    expect_error(run_income_pipeline(options),"file")
    equal(readLines(options$output),"preserve")
    options$output <- fixture_root; expect_error(run_income_pipeline(options),"not empty")
  })
  check("CV fits use fold-only preprocessing and select from recorded fold means", {
    module <- new.env(parent=globalenv())
    for(file in module_files) sys.source(file.path(root,"R",file),envir=module)
    real_fit <- module$fit_income_model; calls <- list()
    module$fit_income_model <- function(kind,x,y,parameter=NULL,seed=12345L,trees=500L) {
      calls[[length(calls)+1L]] <<- list(kind=kind,x=x,y=y,parameter=parameter)
      real_fit(kind,x,y,parameter,seed,trees)
    }
    train <- synthetic_adult(180L,814L,"cv")
    fold_ids <- stratified_group_folds(train,3L,335L)
    expected <- lapply(1:3,function(f) {
      d <- train[fold_ids!=f,,drop=FALSE]; list(x=apply_preprocessor(fit_preprocessor(d),d),y=d$incomelevel)
    })
    bundle <- suppressMessages(module$train_income_models(train,folds=3L,seed=335L,trees=10L,smoke=FALSE))
    stopifnot(length(bundle$models)==5L,nrow(bundle$cv_summary)>5L,
      nrow(bundle$cv_metrics)==3L*nrow(bundle$cv_summary),length(calls)==nrow(bundle$cv_metrics)+5L)
    full_x <- apply_preprocessor(fit_preprocessor(train),train)
    for(call in calls) {
      if(nrow(call$x)==nrow(train)) {equal(call$x,full_x); equal(call$y,train$incomelevel)}
      else {
        matched <- vapply(expected,function(e)isTRUE(all.equal(call$x,e$x))&&identical(call$y,e$y),logical(1))
        stopifnot(any(matched))
      }
    }
    for(kind in kinds) {
      candidates <- bundle$cv_summary[bundle$cv_summary$model==kind,,drop=FALSE]
      selected <- candidates[candidates$selected,,drop=FALSE]
      stopifnot(nrow(selected)==1L,selected$mean_balanced_accuracy==max(candidates$mean_balanced_accuracy))
      for(i in seq_len(nrow(candidates))) {
        fold_rows <- subset(bundle$cv_metrics,model==kind & candidate==candidates$candidate[i])
        equal(candidates$mean_balanced_accuracy[i],mean(fold_rows$balanced_accuracy))
        equal(candidates$sd_balanced_accuracy[i],sd(fold_rows$balanced_accuracy))
      }
    }
    for(kind in kinds) {
      oof <- bundle$oof_predictions[bundle$oof_predictions$model==kind,,drop=FALSE]
      stopifnot(nrow(oof)==nrow(train),!anyDuplicated(oof$row_id),setequal(oof$row_id,train$row_id))
    }
    frozen <- serialize(bundle,NULL); test <- synthetic_adult(40L,915L,"test")
    evaluated <- evaluate_income_models(bundle,test,bootstrap_reps=10L,seed=77L)
    changed <- test; changed$incomelevel <- factor(ifelse(test$incomelevel==">50K","<=50K",">50K"),levels=income_levels)
    flipped <- evaluate_income_models(bundle,changed,bootstrap_reps=10L,seed=77L)
    stopifnot(identical(frozen,serialize(bundle,NULL)))
    columns <- setdiff(names(evaluated$predictions),"truth")
    equal(evaluated$predictions[columns],flipped$predictions[columns])
    stopifnot(all(is.na(evaluated$metrics$brier_score[evaluated$metrics$model=="svm"])))
  })
  check("Pipeline generates checked figures, metrics, diagnostics, and manifests end to end", {
    input <- fixture_dir(); output <- file.path(fixture_dir(),"completed")
    writeLines(raw_lines(synthetic_adult(120L,808L,"train")),file.path(input,"adult.data"))
    writeLines(raw_lines(synthetic_adult(40L,809L,"test")),file.path(input,"adult.test"))
    options <- parse_options(c("--data-dir",input,"--output",output,"--smoke","--trees","10","--folds","3","--bootstrap","20"),root)
    invisible(capture.output(suppressMessages(run_income_pipeline(options))))
    stopifnot(all(c(allowlist,private,"artifact_manifest.csv") %in% list.files(output)))
    manifest <- read.csv(file.path(output,"artifact_manifest.csv"))
    equal(unname(tools::md5sum(file.path(output,manifest$file))),manifest$md5)
    equal(file.info(file.path(output,manifest$file))$size,manifest$bytes)
    metrics <- read.csv(file.path(output,"metrics.csv")); predictions <- read.csv(file.path(output,"predictions.csv"))
    for(kind in kinds) {
      p <- subset(predictions,model==kind)
      recomputed <- income_metrics(factor(p$truth,levels=income_levels),factor(p$prediction,levels=income_levels),p$score)
      actual <- metrics[metrics$model==kind,names(recomputed),drop=FALSE]
      equal(unlist(actual),unlist(recomputed))
    }
    for(plot in plots) {
      header <- readBin(file.path(output,paste0(plot,".png")),"raw",n=24L)
      equal(as.integer(header[1:8]),c(137L,80L,78L,71L,13L,10L,26L,10L))
      stopifnot(readBin(header[17:20],integer(),n=1,size=4,endian="big")>=1800L,
        readBin(header[21:24],integer(),n=1,size=4,endian="big")>=1000L,
        file.info(file.path(output,paste0(plot,".pdf")))$size>1000)
    }
    stopifnot("status: complete" %in% readLines(file.path(output,"run_config.txt")))
    expect_error(export_evidence(output,fixture_dir()),"full runs")
  })
  check("Exporter copies only aggregate evidence and checks public hashes and byte sizes", {
    source <- export_fixture(); destination <- fixture_dir()
    published <- suppressMessages(export_evidence(source,destination))
    equal(sort(published),sort(c(allowlist,"README.md")))
    stopifnot(!any(private %in% list.files(destination)))
    manifest <- read.csv(file.path(destination,"public_artifact_manifest.csv"))
    equal(unname(tools::md5sum(file.path(destination,manifest$file))),manifest$md5)
    equal(file.info(file.path(destination,manifest$file))$size,manifest$bytes)
    expect_error(export_evidence(source,destination),"preserved")
  })
  check("Exporter rejects tampering, bad sizes, unsafe paths, incomplete runs, and unhealthy models", {
    source <- export_fixture(); writeLines("tampered",file.path(source,"metrics.csv"))
    expect_error(export_evidence(source,fixture_dir()),"hashes")
    source <- export_fixture(); path <- file.path(source,"artifact_manifest.csv"); m <- read.csv(path)
    m$bytes[1] <- m$bytes[1]+1; write.csv(m,path,row.names=FALSE)
    expect_error(export_evidence(source,fixture_dir()),"byte")
    m$file[1] <- "../outside"; write.csv(m,path,row.names=FALSE)
    expect_error(export_evidence(source,fixture_dir()),"Invalid")
    for(line in c("mode: smoke","status: running","methodology_version: 1")) {
      source <- export_fixture(); path <- file.path(source,"run_config.txt"); config <- readLines(path)
      key <- sub(":.*$","",line); config[startsWith(config,paste0(key,":"))] <- line
      writeLines(config,path); refresh_manifest(source)
      expect_error(export_evidence(source,fixture_dir()),"complete")
    }
    for(defect in c("fit","convergence","finite","solver","missing")) {
      source <- export_fixture(); path <- file.path(source,"diagnostics.csv"); d <- read.csv(path)
      if(defect=="fit") d$fit_ok[1] <- FALSE
      if(defect=="convergence") d$converged[d$model=="logistic"] <- FALSE
      if(defect=="finite") d$finite_parameters[d$model=="logistic"] <- FALSE
      if(defect=="solver") d$solver_status[d$model=="logistic"] <- 1L
      if(defect=="missing") d <- d[-1,]
      write.csv(d,path,row.names=FALSE); refresh_manifest(source)
      expect_error(export_evidence(source,fixture_dir()),"diagnostic")
    }
    source <- export_fixture(); path <- file.path(source,"input_manifest.csv"); m <- read.csv(path)
    m$md5[1] <- paste(rep("0",32),collapse=""); write.csv(m,path,row.names=FALSE); refresh_manifest(source)
    expect_error(export_evidence(source,fixture_dir()),"reference")
  })
  check("Source/input provenance refuses changed or missing files", {
    paths <- c(fixture_file("first"),fixture_file("second")); expected <- tools::md5sum(paths)
    stopifnot(isTRUE(verify_unchanged(paths,expected,"Test")))
    writeLines("changed",paths[1]); expect_error(verify_unchanged(paths,expected,"Test"),"changed")
    unlink(paths[2]); expect_error(verify_unchanged(paths,expected,"Test"),"finalized")
  })
  cat("\n",passed," tests passed; ",length(failures)," failed.\n",sep="")
  if(length(failures)) stop(paste(failures,collapse="\n"),call.=FALSE)
  invisible(passed)
}
run_income_tests()
