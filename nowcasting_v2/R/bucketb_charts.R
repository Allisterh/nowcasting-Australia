# bucketb_charts.R — visualise the Bucket-B marginal backtest.
# (1) marginal Δ RMSE per series across the 3 windows (negative = improvement)
# (2) absolute RMSE: baseline vs full_bucketb vs v1 reference, per window
# Run from nowcasting_v2/ with R_LIBS -> pipeline lib. Reads cache/bucketb/summary.csv.
source("R/_setup.R")
suppressMessages({ library(ggplot2); library(dplyr); library(tidyr) })

POSTCOVID_FROM <- as.Date("2022-01-01"); OOS_N <- 8L
s <- read.csv("cache/bucketb/summary.csv", stringsAsFactors = FALSE)

v1_metrics <- function() {
  f <- "cache/v1_baseline_r3_backtest.csv"
  if (!file.exists(f)) return(NULL)
  d <- read.csv(f); d <- d[!is.na(d$qoq_error), ]; d$tqd <- as.Date(d$target_quarter_date)
  d <- d[order(d$tqd), ]; rmse <- function(x) if (nrow(x)) sqrt(mean(x$qoq_error^2)) else NA_real_
  c(rmse_full = rmse(d), rmse_pc = rmse(d[d$tqd >= POSTCOVID_FROM, ]),
    rmse_oos = rmse(if (nrow(d) >= OOS_N) tail(d, OOS_N) else d))
}
v1 <- v1_metrics()

win_lab <- c(d_pc = "Post-COVID (2022+)", d_full = "Full sample", d_oos = "OOS last 8q")
win_pal <- c("Post-COVID (2022+)" = "#e8702a", "Full sample" = "#1f77b4", "OOS last 8q" = "#2ca02c")

# ---- Chart 1: marginal deltas (exclude baseline row; keep marg_* + full) ----
m <- s[s$variant != "baseline", ]
m$label <- sub("^marg_", "", m$variant)
m$label[m$variant == "full_bucketb"] <- "FULL (all 9)"
ord <- m$label[order(m$d_pc)]
long <- m |> select(label, d_pc, d_full, d_oos) |>
  pivot_longer(c(d_pc, d_full, d_oos), names_to = "window", values_to = "delta")
long$window <- factor(win_lab[long$window], levels = win_lab)
long$label  <- factor(long$label, levels = rev(ord))

p1 <- ggplot(long, aes(delta, label, colour = window)) +
  geom_vline(xintercept = 0, colour = "grey40", linewidth = 0.6) +
  geom_point(size = 2.6, alpha = 0.9) +
  facet_wrap(~window, nrow = 1) +
  scale_colour_manual(values = win_pal, guide = "none") +
  labs(title = "Bucket-B marginal contribution — ΔRMSE vs 29-series baseline",
       subtitle = "Left of 0 (negative) = the series IMPROVES the nowcast. Headline config (qa, α=0.05).",
       x = "ΔRMSE vs baseline (pp QoQ GDP)", y = NULL) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(), strip.text = element_text(face = "bold"),
        axis.text.y = element_text(size = 9))
ggsave("bucketb_marginal_delta.png", p1, width = 11, height = 4.8, dpi = 150, bg = "white")
cat("wrote bucketb_marginal_delta.png\n")

# ---- Chart 2: absolute RMSE baseline vs full vs v1 ----
key <- s[s$variant %in% c("baseline", "full_bucketb"), ]
abs_long <- key |> select(variant, rmse_pc, rmse_full, rmse_oos) |>
  pivot_longer(c(rmse_pc, rmse_full, rmse_oos), names_to = "window", values_to = "rmse")
abs_long$window <- factor(c(rmse_pc="Post-COVID (2022+)", rmse_full="Full sample",
                            rmse_oos="OOS last 8q")[abs_long$window],
                          levels = c("Post-COVID (2022+)","Full sample","OOS last 8q"))
p2 <- ggplot(abs_long, aes(rmse, variant, fill = variant)) +
  geom_col(width = 0.6, show.legend = FALSE) +
  facet_wrap(~window, nrow = 1, scales = "free_x") +
  geom_text(aes(label = sprintf("%.3f", rmse)), hjust = -0.1, size = 3) +
  scale_fill_manual(values = c(baseline = "#888888", full_bucketb = "#e8702a")) +
  labs(title = "Baseline (29) vs Full Bucket-B (38) — absolute RMSE by window",
       subtitle = if (!is.null(v1)) sprintf("v1 (13-DFM) ref: postCOVID %.3f / full %.3f / OOS8 %.3f",
                    v1["rmse_pc"], v1["rmse_full"], v1["rmse_oos"]) else "lower = better",
       x = "RMSE (pp QoQ GDP)", y = NULL) +
  coord_cartesian(clip = "off") +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(), strip.text = element_text(face = "bold"),
        plot.margin = margin(5, 30, 5, 5))
ggsave("bucketb_abs_rmse.png", p2, width = 11, height = 3.2, dpi = 150, bg = "white")
cat("wrote bucketb_abs_rmse.png\n")
