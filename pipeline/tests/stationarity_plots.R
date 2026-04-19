#### Diagnostic plots: raw level vs transformed series ####
# Produces a PDF with one page per indicator, showing:
#   • top panel: raw level series with COVID period shaded
#   • bottom panel: transformed series (the input to the DFM)
# ADF/KPSS p-values overlaid as subtitle for quick reference.

suppressPackageStartupMessages({
  library(tidyverse)
  library(tseries)
  library(glue)
  library(patchwork)
})

# Share trans logic with stationarity_check.R
source("pipeline/tests/stationarity_check.R", local = TRUE, chdir = FALSE)

# Load data + metadata
master <- readRDS("pipeline/.cache/processed/master_dataset_wide.rds")
meta   <- readRDS("pipeline/seed/component_metadata.rds")$indicators

# Order to plot: same order as metadata indicators table (excluding GDP last)
plot_order <- meta |>
  arrange(component_id, indicator_id) |>
  pull(indicator_id)

covid_start <- as.Date("2020-03-01")
covid_end   <- as.Date("2020-07-31")

run_p <- function(series) {
  x <- series[!is.na(series)]
  if (length(x) < 24) return(list(adf = NA, kpss = NA))
  list(
    adf  = suppressWarnings(tryCatch(adf.test(x)$p.value, error = function(e) NA)),
    kpss = suppressWarnings(tryCatch(kpss.test(x)$p.value, error = function(e) NA))
  )
}

make_page <- function(ind_id) {
  row <- meta |> filter(indicator_id == ind_id)
  if (nrow(row) == 0) return(NULL)
  code <- row$trans_code[1]
  if (!ind_id %in% names(master)) return(NULL)

  dates <- master$date
  raw   <- master[[ind_id]]
  trans <- apply_trans(raw, code)

  # Tests on COVID-masked transformed series (what the model sees)
  trans_masked <- trans
  trans_masked[dates >= covid_start & dates <= covid_end] <- NA
  p <- run_p(trans_masked)

  df_raw   <- tibble(date = dates, value = raw)   |> filter(!is.na(value))
  df_trans <- tibble(date = dates, value = trans) |> filter(!is.na(value))

  title <- glue("{row$indicator_name} [{ind_id}] — trans code {code} ({trans_label(code)})")
  subtitle <- glue(
    "{row$trans_rationale} · ",
    "COVID-masked ADF p={sprintf('%.3f', p$adf)}, KPSS p={sprintf('%.3f', p$kpss)}"
  )

  p_raw <- ggplot(df_raw, aes(date, value)) +
    annotate("rect", xmin = covid_start, xmax = covid_end,
             ymin = -Inf, ymax = Inf, fill = "#E8A398", alpha = 0.35) +
    geom_line(colour = "#2F5C7E") +
    labs(subtitle = "raw level", x = NULL, y = NULL) +
    theme_minimal(base_size = 10) +
    theme(plot.subtitle = element_text(size = 9, colour = "grey30"))

  p_trans <- ggplot(df_trans, aes(date, value)) +
    annotate("rect", xmin = covid_start, xmax = covid_end,
             ymin = -Inf, ymax = Inf, fill = "#E8A398", alpha = 0.35) +
    geom_hline(yintercept = 0, linetype = "dashed", colour = "grey60") +
    geom_line(colour = "#2F7E5B") +
    labs(subtitle = glue("transformed ({trans_label(code)})"), x = NULL, y = NULL) +
    theme_minimal(base_size = 10) +
    theme(plot.subtitle = element_text(size = 9, colour = "grey30"))

  (p_raw / p_trans) +
    plot_annotation(title = title, subtitle = subtitle,
                    theme = theme(
                      plot.title = element_text(size = 12, face = "bold"),
                      plot.subtitle = element_text(size = 10, colour = "grey25")
                    ))
}

out_pdf <- "pipeline/.cache/stationarity_diagnostic.pdf"
pdf(out_pdf, width = 10, height = 7)
for (ind in plot_order) {
  p <- make_page(ind)
  if (!is.null(p)) print(p)
}
dev.off()

cat(glue("Wrote {out_pdf}\n"))
