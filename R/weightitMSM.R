weightitMSM <- function(formula.list, data = NULL, method = "ps", stabilize = FALSE, by = NULL, s.weights = NULL,
                        num.formula = NULL, moments = NULL, int = FALSE, missing = NULL,
                        verbose = FALSE, include.obj = FALSE, is.MSM.method, weightit.force = FALSE, ...) {

  A <- list(...)

  call <- match.call()

  ## Checks and processing ----

  #Checks

  ##Process method
  check.acceptable.method(method, msm = TRUE, force = weightit.force)

  if (is.character(method)) {
    method <- method.to.proper.method(method)
    attr(method, "name") <- method
    if (missing(is.MSM.method)) is.MSM.method <- NULL
    is.MSM.method <- process.MSM.method(is.MSM.method, method)
  }
  else if (is.function(method)) {
    method.name <- paste(deparse(substitute(method)))
    check.user.method(method)
    if (missing(is.MSM.method)) is.MSM.method <- NULL
    is.MSM.method <- process.MSM.method(is.MSM.method, method)
    attr(method, "name") <- method.name
  }

  #Process moments and int
  moments.int <- process.moments.int(moments, int, method)
  moments <- moments.int[["moments"]]; int <- moments.int[["int"]]

  s.weights <- process.s.weights(s.weights, data)

  if (is_not_null(num.formula)) {
    if (!stabilize) {
      message("Setting stabilize to TRUE based on num.formula input.")
    }
    stabilize <- TRUE
  }
  if (stabilize) {
    if (is_not_null(num.formula)) {
      if (is.formula(num.formula)) {
        if (is.formula(num.formula, sides = 1)) {
          rhs.vars.mentioned.lang <- attr(terms(num.formula), "variables")[-1]
          rhs.vars.mentioned <- sapply(rhs.vars.mentioned.lang, deparse)
          rhs.vars.failed <- sapply(rhs.vars.mentioned.lang, function(v) {
            null_or_error(try(eval(v, c(data, .GlobalEnv)), silent = TRUE))
          })

          if (any(rhs.vars.failed)) {
            stop(paste0(c("All variables in formula must be variables in data or objects in the global environment.\nMissing variables: ",
                          paste(rhs.vars.mentioned[rhs.vars.failed], collapse=", "))), call. = FALSE)
          }
        }
        else {
          stop("The argument to num.formula must have right hand side variables but not a response variable (e.g., ~ V1 + V2).", call. = FALSE)
        }
      }
      else {
        stop("The argument to num.formula must be a single formula with no response variable and with the stabilization factors on the right hand side.", call. = FALSE)
      }
    }
  }

  ##Process by
  if (is_not_null(A[["exact"]])) {
    message("'by' has replaced 'exact' in the weightit() syntax, but 'exact' will always work.")
    # by.name <- deparse(A[["exact"]])
    by <- A[["exact"]]
    by.arg <- "exact"
  }
  else by.arg <- "by"

  reported.covs.list <- covs.list <- treat.list <- w.list <- ps.list <-
    stabout <- sw.list <- make_list(length(formula.list))

  if (is_null(formula.list) || !is_(formula.list, "list") || !all(vapply(formula.list, is.formula, logical(1L), sides = 2))) {
    stop("'formula.list' must be a list of formulas.", call. = FALSE)
  }

  for (i in seq_along(formula.list)) {

    #Process treat and covs from formula and data
    t.c <- get.covs.and.treat.from.formula(formula.list[[i]], data)
    reported.covs.list[[i]] <- t.c[["reported.covs"]]
    covs.list[[i]] <- t.c[["model.covs"]]
    treat.list[[i]] <- t.c[["treat"]]
    treat.name <- t.c[["treat.name"]]
    names(treat.list)[i] <- treat.name
    names(reported.covs.list)[i] <- treat.name

    if (is_null(covs.list[[i]])) stop("No covariates were specified in the ", ordinal(i), " formula.", call. = FALSE)
    if (is_null(treat.list[[i]])) stop("No treatment variable was specified in the ", ordinal(i), " formula.", call. = FALSE)

    n <- length(treat.list[[i]])

    if (nrow(covs.list[[i]]) != n) {
      stop("Treatment and covariates must have the same number of units.", call. = FALSE)
    }
    if (anyNA(treat.list[[i]])) {
      stop(paste0("No missing values are allowed in the treatment variable. Missing values found in ", treat.name, "."), call. = FALSE)
    }
    if (anyNA(reported.covs.list[[i]])) {
      warning("Missing values are present in the covariates. See ?weightit for information on how these are handled.", call. = FALSE)
    }

    treat.list[[i]] <- assign.treat.type(treat.list[[i]])

    #By is processed each for each time, but only last time is used for by.factor.
    processed.by <- process.by(by, data = data,
                               treat = treat.list[[i]],
                               treat.name = treat.name,
                               by.arg = by.arg)

    #Process missing
    if (anyNA(reported.covs.list[[i]])) {
      missing <- process.missing(missing, method, get.treat.type(treat.list[[i]]))
    }
    else if (i == length(formula.list)) missing <- ""

  }

  if (is_null(s.weights)) s.weights <- rep(1, n)

  if (verbose) eval.verbose <- base::eval
  else eval.verbose <- utils::capture.output

  if (is.MSM.method) {
    eval.verbose({
      #Returns weights (w)
      obj <- do.call("weightit.fit", c(list(covs = covs.list,
                                            treat = treat.list,
                                            s.weights = s.weights,
                                            by.factor = attr(processed.by, "by.factor"),
                                            stabilize = stabilize,
                                            method = method,
                                            moments = moments,
                                            int = int,
                                            ps = NULL,
                                            missing = missing,
                                            is.MSM.method = TRUE,
                                            include.obj = include.obj), A))
    })
    w <- obj[["weights"]]
    stabout <- NULL
    obj.list <- obj[["fit.obj"]]
  }
  else {
    A[["estimand"]] <- NULL
    estimand <- "ATE"

    if (length(A[["link"]]) %nin% c(0, 1, length(formula.list))) stop(paste0("The argument to link must have length 1 or ", length(formula.list), "."), call. = FALSE)
    else if (length(A[["link"]]) == 1) A[["link"]] <- rep(A[["link"]], length(formula.list))
    # if (length(A[["family"]]) %nin% c(0, 1, length(formula.list))) stop(paste0("The argument to link must have length 1 or ", length(formula.list), "."), call. = FALSE)
    # if (length(A[["family"]]) == 1) A[["family"]] <- rep(A[["family"]], length(formula.list))

    obj.list <- make_list(length(formula.list))

    for (i in seq_along(formula.list)) {
      A_i <- A
      if (is_not_null(A[["link"]])) A_i[["link"]] <- A[["link"]][[i]]

      ## Running models ----

      eval.verbose({
        #Returns weights (w) and propensty score (ps)
        obj <- do.call("weightit.fit", c(list(covs = covs.list[[i]],
                                              treat = treat.list[[i]],
                                              treat.type = get.treat.type(treat.list[[i]]),
                                              s.weights = s.weights,
                                              by.factor = attr(processed.by, "by.factor"),
                                              estimand = estimand,
                                              focal = NULL,
                                              stabilize = FALSE,
                                              method = method,
                                              moments = moments,
                                              int = int,
                                              ps = NULL,
                                              missing = missing,
                                              is.MSM.method = FALSE,
                                              include.obj = include.obj
                                              ), A_i))
      })
      w.list[[i]] <- obj[["weights"]]
      ps.list[[i]] <- obj[["ps"]]
      obj.list[[i]] <- obj[["fit.obj"]]

      if (stabilize) {
        #Process stabilization formulas and get stab weights
        if (is.formula(num.formula)) {
          if (i == 1) {
            stab.f <- update.formula(as.formula(paste(names(treat.list)[i], "~ 1")), as.formula(paste(paste(num.formula, collapse = ""), "+ .")))
          }
          else {
            stab.f <- update.formula(as.formula(paste(names(treat.list)[i], "~", paste(names(treat.list)[seq_along(names(treat.list)) < i], collapse = " * "))), as.formula(paste(num.formula, "+ .")))
          }
        }
        else {
          if (i == 1) {
            stab.f <- as.formula(paste(names(treat.list)[i], "~ 1"))
          }
          else {
            stab.f <- as.formula(paste(names(treat.list)[i], "~", paste(names(treat.list)[seq_along(names(treat.list)) < i], collapse = " * ")))
          }
        }
        stab.t.c_i <- get.covs.and.treat.from.formula(stab.f, data)
        stab.covs_i <- stab.t.c_i[["model.covs"]]

        eval.verbose({
          sw_obj <- do.call("weightit.fit", c(list(covs = stab.covs_i,
                                                   treat = treat.list[[i]],
                                                   treat.type = get.treat.type(treat.list[[i]]),
                                                   s.weights = s.weights,
                                                   by.factor = attr(processed.by, "by.factor"),
                                                   estimand = estimand,
                                                   focal = NULL,
                                                   stabilize = FALSE,
                                                   method = "ps",
                                                   moments = NULL,
                                                   int = FALSE,
                                                   ps = NULL,
                                                   missing = missing), A))
        })
        sw.list[[i]] <- 1/sw_obj[["weights"]]
        stabout[[i]] <- stab.f[-2]

      }

    }

    w <- Reduce("*", w.list)

    if (stabilize) {
      sw <- Reduce("*", sw.list)
      w <- w*sw

      unique.stabout <- unique(stabout)
      if (length(unique.stabout) <= 1) stabout <- unique.stabout
    }
    else stabout <- NULL
  }


  if (all_the_same(w)) stop(paste0("All weights are ", w[1], "."), call. = FALSE)
  if (all(sapply(ps.list, is_null))) ps.list <- NULL
  else names(ps.list) <- names(treat.list)

  if (include.obj) names(obj.list) <- names(treat.list)

  ## Assemble output object----
  out <- list(weights = w,
              treat.list = treat.list,
              covs.list = reported.covs.list,
              #data = data,
              estimand = if (exists("estimand")) estimand else "ATE",
              method = method,
              ps.list = ps.list,
              s.weights = s.weights,
              #discarded = NULL,
              by = processed.by,
              call = call,
              stabilization = stabout,
              obj = obj.list
  )

  out <- clear_null(out)

  class(out) <- c("weightitMSM", "weightit")

  return(out)
  ####----
}

print.weightitMSM <- function(x, ...) {
  treat.types <- vapply(x[["treat.list"]], get.treat.type, character(1L))
  trim <- attr(x[["weights"]], "trim")

  cat("A " %+% italic("weightitMSM") %+% " object\n")
  cat(paste0(" - method: \"", attr(x[["method"]], "name"), "\" (", method.to.phrase(x[["method"]]), ")\n"))
  cat(paste0(" - number of obs.: ", length(x[["weights"]]), "\n"))
  cat(paste0(" - sampling weights: ", ifelse(all_the_same(x[["s.weights"]]), "none", "present"), "\n"))
  cat(paste0(" - number of time points: ", length(x[["treat.list"]]), " (", paste(names(x[["treat.list"]]), collapse = ", "), ")\n"))
  cat(paste0(" - treatment: \n",
             paste0(sapply(1:length(x$covs.list), function(i) {

               paste0("    + time ", i, ": ", ifelse(treat.types[i] == "continuous", "continuous", paste0(nunique(x[["treat.list"]][[i]]), "-category", ifelse(treat.types[i] == "multinomial", paste0(" (", paste(levels(x[["treat.list"]][[i]]), collapse = ", "), ")"), ""))), "\n")

             }), collapse = ""), collapse = "\n"))
  cat(paste0(" - covariates: \n",
             paste0(sapply(1:length(x$covs.list), function(i) {
               if (i == 1) {
                 paste0("    + baseline: ", if (is_null(x$covs.list[[i]])) "(none)" else paste(names(x$covs.list[[i]]), collapse = ", "), "\n")
               }
               else {
                 paste0("    + after time ", i-1, ": ", paste(names(x$covs.list[[i]]), collapse = ", "), "\n")
               }
             }), collapse = ""), collapse = "\n"))
  if (is_not_null(x[["by"]])) {
    cat(paste0(" - by: ", paste(names(x[["by"]]), collapse = ", "), "\n"))
  }
  if (is_not_null(x$stabilization)) {
    cat(" - stabilized")
    if (any(sapply(x$stabilization, function(s) is_not_null(all.vars(s))))) {
      cat(paste0("; stabilization factors:\n", if (length(x$stabilization) == 1) paste0("      ", paste0(attr(terms(x[["stabilization"]][[1]]), "term.labels"), collapse = ", "))
                 else {
                   paste0(sapply(1:length(x$stabilization), function(i) {
                     if (i == 1) {
                       paste0("    + baseline: ", if (is_null(attr(terms(x[["stabilization"]][[i]]), "term.labels"))) "(none)" else paste(attr(terms(x[["stabilization"]][[i]]), "term.labels"), collapse = ", "))
                     }
                     else {
                       paste0("    + after time ", i-1, ": ", paste(attr(terms(x[["stabilization"]][[i]]), "term.labels"), collapse = ", "))
                     }
                   }), collapse = "\n")
                 }))
    }
  }

  if (is_not_null(trim)) {
    if (trim < 1) {
      if (attr(x[["weights"]], "trim.lower")) trim <- c(1 - trim, trim)
      cat(paste(" - weights trimmed at", word_list(paste0(round(100*trim, 2), "%")), "\n"))
    }
    else {
      if (attr(x[["weights"]], "trim.lower")) t.b <- "top and bottom" else t.b <- "top"
      cat(paste(" - weights trimmed at the", t.b, trim, "\n"))
    }
  }
  invisible(x)
}
summary.weightitMSM <- function(object, top = 5, ignore.s.weights = FALSE, ...) {
  outnames <- c("weight.range", "weight.top",
                "coef.of.var", "scaled.mad", "negative.entropy",
                "weight.mean",
                "effective.sample.size")

  out.list <- make_list(names(object$treat.list))

  if (ignore.s.weights || is_null(object$s.weights)) sw <- rep(1, length(object$weights))
  else sw <- object$s.weights
  w <- object$weights*sw
  treat.types <- vapply(object[["treat.list"]], get.treat.type, character(1L))
  stabilized <- is_not_null(object[["stabilization"]])

  for (ti in seq_along(object$treat.list)) {
    out <- make_list(outnames)
    if (treat.types[ti] == "continuous") {
      out$weight.range <- list(all = c(min(w[w > 0]),
                                       max(w[w > 0])))
      top.weights <- sort(w, decreasing = TRUE)[seq_len(top)]
      out$weight.top <- list(all = sort(setNames(top.weights, which(w %in% top.weights)[seq_len(top)])))
      out$coef.of.var <- c(all = sd(w)/mean_fast(w))
      out$scaled.mad <- c(all = mean.abs.dev(w)/mean_fast(w))
      out$negative.entropy <- c(all = sum(w[w>0]*log(w[w>0]))/sum(w[w>0]))
      out$num.zeros <- c(overall = sum(check_if_zero(w)))
      out$weight.mean <- if (stabilized) mean_fast(w) else NULL

      nn <- make_df("Total", c("Unweighted", "Weighted"))
      nn["Unweighted", ] <- ESS(sw)
      nn["Weighted", ] <- ESS(w)

      out$effective.sample.size <- nn

      out.list[[ti]] <- out

    }
    else if (treat.types[ti] == "binary") {
      t <- object$treat.list[[ti]]
      top0 <- c(treated = min(top, sum(t == 1)),
                control = min(top, sum(t == 0)))
      out$weight.range <- list(treated = c(min(w[w > 0 & t == 1]),
                                           max(w[w > 0 & t == 1])),
                               control = c(min(w[w > 0 & t == 0]),
                                           max(w[w > 0 & t == 0])))
      top.weights <- list(treated = sort(w[t == 1], decreasing = TRUE)[seq_len(top0["treated"])],
                          control = sort(w[t == 0], decreasing = TRUE)[seq_len(top0["control"])])
      out$weight.top <- setNames(lapply(names(top.weights), function(x) sort(setNames(top.weights[[x]], which(w %in% top.weights[[x]] & t == {if (x == "control") 0 else 1})[seq_len(top0[x])]))),
                                 names(top.weights))
      top.weights <- list(treated = sort(w[t == 1], decreasing = TRUE)[seq_len(top0["treated"])],
                          control = sort(w[t == 0], decreasing = TRUE)[seq_len(top0["control"])])

      out$coef.of.var <- c(treated = sd(w[t==1])/mean_fast(w[t==1]),
                           control = sd(w[t==0])/mean_fast(w[t==0]),
                           overall = sd(w)/mean_fast(w))
      out$scaled.mad <- c(treated = mean.abs.dev(w[t==1])/mean_fast(w[t==1]),
                          control = mean.abs.dev(w[t==0])/mean_fast(w[t==0]),
                          overall = mean.abs.dev(w)/mean_fast(w))
      out$negative.entropy <- c(treated = sum(w[t==1 & w>0]*log(w[t==1 & w>0]))/sum(w[t==1 & w>0]),
                                control = sum(w[t==0 & w>0]*log(w[t==0 & w>0]))/sum(w[t==0 & w>0]),
                                overall = sum(w[w>0]*log(w[w>0]))/sum(w[w>0]))
      out$num.zeros <- c(treated = sum(check_if_zero(w[t==1])),
                         control = sum(check_if_zero(w[t==0])),
                         overall = sum(check_if_zero(w)))
      out$weight.mean <- if (stabilized) mean_fast(w) else NULL

      nn <- make_df(c("Control", "Treated"), c("Unweighted", "Weighted"))
      nn["Unweighted", ] <- c(ESS(sw[t==0]),
                              ESS(sw[t==1]))
      nn["Weighted", ] <- c(ESS(w[t==0]),
                            ESS(w[t==1]))

      out$effective.sample.size <- nn
      out.list[[ti]] <- out

    }
    else if (treat.types[ti] == "multinomial") {
      t <- object$treat.list[[ti]]
      out$weight.range <- setNames(lapply(levels(t), function(x) c(min(w[w > 0 & t == x]),
                                                                   max(w[w > 0 & t == x]))),
                                   levels(t))
      top.weights <- setNames(lapply(levels(t), function(x) sort(w[t == x], decreasing = TRUE)[seq_len(top)]),
                              levels(t))
      out$weight.top <- setNames(lapply(names(top.weights), function(x) sort(setNames(top.weights[[x]], which(w %in% top.weights[[x]] & t == x)[seq_len(top)]))),
                                 names(top.weights))
      out$coef.of.var <- c(vapply(levels(t), function(x) sd(w[t==x])/mean_fast(w[t==x]), numeric(1L)),
                           overall = sd(w)/mean_fast(w))
      out$scaled.mad <- c(vapply(levels(t), function(x) mean.abs.dev(w[t==x])/mean_fast(w[t==x]), numeric(1L)),
                          overall = mean.abs.dev(w)/mean_fast(w))
      out$negative.entropy <- c(vapply(levels(t), function(x) sum(w[t==x & w>0]*log(w[t==x & w>0]))/sum(w[t==x & w>0]), numeric(1L)),
                                overall = sum(w[w>0]*log(w[w>0]))/sum(w[w>0]))
      out$num.zeros <- c(vapply(levels(t), function(x) sum(check_if_zero(w[t==x])), numeric(1L)),
                         overall = sum(check_if_zero(w)))
      out$weight.mean <- if (stabilized) mean_fast(w) else NULL

      nn <- make_df(levels(t), c("Unweighted", "Weighted"))
      for (i in levels(t)) {
        nn["Unweighted", i] <- ESS(sw[t==i])
        nn["Weighted", i] <- ESS(w[t==i])
      }

      out$effective.sample.size <- nn
      out.list[[ti]] <- out
    }
    else if (treat.types[ti] == "ordinal") {
      warning("Sneaky, sneaky! Ordinal coming soon :)", call. = FALSE)
    }
  }

  class(out.list) <- "summary.weightitMSM"
  attr(out.list, "weights") <- w
  return(out.list)
}
print.summary.weightitMSM <- function(x, ...) {
  if (all(vapply(x, function(y) isTRUE(all.equal(x[[1]], y)), logical(1L)))) {
    only.one <- TRUE
  }
  else only.one <- FALSE

  cat(paste(rep(" ", 17), collapse = "") %+% underline("Summary of weights") %+% "\n\n")
  for (ti in seq_along(x)) {
    if (!only.one) cat(strikethrough(paste(rep(" ", 22), collapse = "")) %+% italic(" Time " %+% ti %+% " ") %+% strikethrough(paste(rep(" ", 22), collapse = "")) %+% "\n")
    tryCatch({
      cat("- " %+% italic("Weight ranges") %+% ":\n\n")
      print.data.frame(round_df_char(text_box_plot(x[[ti]]$weight.range, 28), 4))
    })

    df <- setNames(data.frame(do.call("c", lapply(names(x[[ti]]$weight.top), function(y) c(" ", y))),
                              matrix(do.call("c", lapply(x[[ti]]$weight.top, function(y) c(names(y), round(y, 4)))),
                                     byrow = TRUE, nrow = 2*length(x[[ti]]$weight.top))),
                   rep("", 1 + length(x[[ti]]$weight.top[[1]])))
    cat("\n- " %+% italic("Units with", length(x[[ti]]$weight.top[[1]]), "greatest weights by group") %+% ":\n")
    print.data.frame(df, row.names = FALSE)
    cat("\n- " %+% italic("Weight statistics") %+% ":\n\n")
    print.data.frame(round_df_char(setNames(as.data.frame(cbind(x[[ti]]$coef.of.var,
                                                                x[[ti]]$scaled.mad,
                                                                x[[ti]]$negative.entropy,
                                                                x[[ti]]$num.zeros)),
                                            c("Coef of Var", "MAD", "Entropy", "# Zeros")), 3))

    if (is_not_null(x[[ti]][["weight.mean"]])) cat("\n- " %+% italic("Mean of Weights") %+% " = " %+% round(x[[ti]][["weight.mean"]], 4) %+% "\n")

    cat("\n- " %+% italic("Effective Sample Sizes") %+% ":\n\n")
    print.data.frame(round_df_char(x[[ti]]$effective.sample.size, 2, pad = " "))
    cat("\n")
    if (only.one) break
  }

  invisible(x)
}
