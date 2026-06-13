# plot_model_comparison.R
# Cross-model RMSE landscape: every sweep variant (Stage A panels + Stage B
# hyperparameters) ranked by post-COVID RMSE, with full-sample and OOS-8q RMSE
# alongside, and v1 (13-series DFM) drawn as dashed reference lines per window.
# Companion to plot_sweep_results.R (which does the best-variant time series).
# Usage (run from nowcasting_v2/, R_LIBS -> pipeline lib): Rscript R/plot_model_comparison.R
source("R/_setup.R")
suppressMessages({ library(ggplot2); library(dplyr); library(tidyr) })

POSTCOVID_FROM <- as.Date("2022-01-01")
OOS_N <- 8L

# --- v1 reference metrics, computed the same way sweep_v2.R's .metrics() does ---
v1_metrics <- function() {
  d <- read.csv("cache/v1_baseline_r3_backtest.csv")
  d <- d[!is.na(d$qoq_error), ]
  d$tqd <- as.Date(d$target_quarter_date)
  d <- d[order(d$tqd), ]
  rmse <- function(x) if (nrow(x)) sqrt(mean(x$qoq_error^2)) else NA_real_
  pc  <- d[d$tqd >= POSTCOVID_FROM, ]
  oos <- if (nrow(d) >= OOS_N) tail(d, OOS_N) else d
  c(rmse_full = rmse(d), rmse_pc = rmse(pc), rmse_oos = rmse(oos))
}

s <- read.csv("cache/sweep_v2/summary.csv")
v1 <- v1_metrics()
cat(sprintf("v1 reference: full=%.3f  postCOVID=%.3f  OOS8=%.3f\n",
            v1["rmse_full"], v1["rmse_pc"], v1["rmse_oos"]))

# Rank variants by the headline metric (post-COVID RMSE), best at top.
s <- s |> arrange(rmse_pc)
s$variant <- factor(s$variant, levels = rev(s$variant))

# Tidy label: mark Stage A panels vs Stage B hyperparameter variants.
s <- s |> mutate(grp = ifelse(stage == "A", "Stage A: panel", "Stage B: hyperparam"))

long <- s |>
  select(variant, grp, rmse_full, rmse_pc, rmse_oos) |>
  pivot_longer(c(rmse_full, rmse_pc, rmse_oos), names_to = "window", values_to = "rmse") |>
  filter(!is.na(rmse))
long$window <- factor(long$window,
  levels = c("rmse_pc", "rmse_full", "rmse_oos"),
  labels = c("Post-COVID (2022+)", "Full sample", "OOS last 8q"))

win_pal <- c("Post-COVID (2022+)" = "#e8702a", "Full sample" = "#1f77b4",
             "OOS last 8q" = "#2ca02c")
vref <- data.frame(
  window = factor(c("Post-COVID (2022+)","Full sample","OOS last 8q"),
                  levels = levels(long$window)),
  x = c(v1["rmse_pc"], v1["rmse_full"], v1["rmse_oos"]))

p <- ggplot(long, aes(rmse, variant)) +
  geom_vline(data = vref, aes(xintercept = x), colour = "grey45",
             linetype = "dashed", linewidth = 0.5) +
  geom_point(aes(colour = window), size = 2.6, alpha = 0.9) +
  facet_wrap(~window, nrow = 1, scales = "free_x") +
  scale_colour_manual(values = win_pal, guide = "none") +
  labs(
    title = "Nowcast model sweep — RMSE by variant (lower = better)",
    subtitle = "Dashed grey = v1 (13-series DFM) reference. Variants sorted by post-COVID RMSE.",
    x = "RMSE (pp of QoQ GDP growth)", y = NULL) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(),
        panel.grid.major.y = element_line(colour = "grey92"),
        strip.text = element_text(face = "bold"),
        axis.text.y = element_text(size = 8))

 h <- max(4.5, 0.28 * nlevels(long$variant) + 1.5)
ggsave("model_comparison_rmse.png", p, width = 11, height = h, dpi = 150, bg = "white")
cat("wrote model_comparison_rmse.png ;", nlevels(s$variant), "variants\n")
