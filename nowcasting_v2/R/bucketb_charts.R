# bucketb_charts.R — visualise the Bucket-B experiment.
# (1) Wald selection ranking: every candidate by univariate Wald stat vs GDP, with
#     Bucket-B highlighted and the α=0.05/0.10/0.20 selection thresholds. This is
#     the chart that explains the null α=0.05 result.
# (2) α-sweep ΔRMSE: when credit_personal / non_res_ba DO get selected (α=0.10/0.20),
#     their actual accuracy impact vs that α's baseline.
# Run from nowcasting_v2/ with R_LIBS -> pipeline lib.
source("R/_setup.R")
suppressMessages({ library(ggplot2); library(dplyr); library(tidyr) })

# ---- Chart 1: Wald ranking ----
w <- read.csv("cache/bucketb/wald.csv", stringsAsFactors = FALSE)
w <- w[!is.na(w$Stat), ]
w$series <- factor(w$series, levels = w$series[order(w$Stat)])
w$grp <- ifelse(w$bucketb, "Bucket-B candidate", "current v2 panel")
p1 <- ggplot(w, aes(Stat, series, colour = grp)) +
  geom_vline(xintercept = c(7.815, 6.251, 4.642), linetype = c("solid","dashed","dotted"),
             colour = "grey50", linewidth = 0.5) +
  geom_point(size = 2.6, alpha = 0.9) +
  scale_colour_manual(values = c("Bucket-B candidate" = "#e8702a", "current v2 panel" = "#1f77b4"),
                      name = NULL) +
  labs(title = "Targeted-predictor selection — univariate Wald stat vs QoQ GDP",
       subtitle = "Lines = selection thresholds: solid α=0.05 (production), dashed α=0.10, dotted α=0.20.\nSeries right of a line are SELECTED at that α. Bucket-B in orange.",
       x = "Wald statistic (χ², df=3)", y = NULL) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(), legend.position = "top",
        axis.text.y = element_text(size = 8))
ggsave("bucketb_wald_ranking.png", p1, width = 9, height = 7, dpi = 150, bg = "white")
cat("wrote bucketb_wald_ranking.png\n")

# ---- Chart 2: α-sweep ΔRMSE (if the follow-up sweep has run) ----
f <- "cache/bucketb/summary_alpha.csv"
if (file.exists(f)) {
  s <- read.csv(f, stringsAsFactors = FALSE)
  s <- s[!grepl("^base_", s$variant), ]
  lab <- c(cp = "+credit_personal", nrb = "+non_res_ba", both = "+both")
  s$series <- lab[sub("_a.*$", "", s$variant)]
  s$alpha_lab <- paste0("α=", sprintf("%.2f", s$alpha))
  long <- s |> select(series, alpha_lab, d_pc, d_full, d_oos) |>
    pivot_longer(c(d_pc, d_full, d_oos), names_to = "window", values_to = "delta")
  long$window <- factor(c(d_pc="Post-COVID", d_full="Full", d_oos="OOS8")[long$window],
                        levels = c("Post-COVID","Full","OOS8"))
  p2 <- ggplot(long, aes(delta, series, fill = window)) +
    geom_vline(xintercept = 0, colour = "grey40", linewidth = 0.6) +
    geom_col(position = position_dodge(width = 0.7), width = 0.6) +
    facet_wrap(~alpha_lab, nrow = 1) +
    scale_fill_manual(values = c("Post-COVID"="#e8702a","Full"="#1f77b4","OOS8"="#2ca02c"), name=NULL) +
    labs(title = "Marginal ΔRMSE when the near-miss series ARE selected (α=0.10/0.20)",
         subtitle = "vs that α's own baseline. Left of 0 = improvement.",
         x = "ΔRMSE (pp QoQ GDP)", y = NULL) +
    theme_minimal(base_size = 11) +
    theme(panel.grid.minor = element_blank(), legend.position = "top",
          strip.text = element_text(face = "bold"))
  ggsave("bucketb_alpha_delta.png", p2, width = 10, height = 3.6, dpi = 150, bg = "white")
  cat("wrote bucketb_alpha_delta.png\n")
} else cat("(summary_alpha.csv not ready — skipping chart 2)\n")
