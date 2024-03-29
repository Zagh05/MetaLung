suppressMessages(library("phyloseq",quietly = TRUE, warn.conflicts = FALSE))
suppressMessages(library("ggplot2",quietly = TRUE, warn.conflicts = FALSE))
suppressMessages(library("RColorBrewer",quietly = TRUE, warn.conflicts = FALSE))
suppressMessages(library("patchwork",quietly = TRUE, warn.conflicts = FALSE))
suppressMessages(library("vegan",quietly = TRUE, warn.conflicts = FALSE))
suppressMessages(library("tidyverse",quietly = TRUE, warn.conflicts = FALSE))
suppressMessages(library("readr",quietly = TRUE, warn.conflicts = FALSE))
suppressMessages(library("dplyr",quietly = TRUE, warn.conflicts = FALSE))
suppressMessages(library("tibble",quietly = TRUE, warn.conflicts = FALSE))
suppressMessages(library("plyr", quietly = TRUE, warn.conflicts = FALSE))

phylo_obj <- unlist(snakemake@input[["phylo_obj"]])
method <- snakemake@params[["method"]]
distance <- snakemake@params[["distance"]]
color <- snakemake@params[["color"]]
shape <- snakemake@params[["shape"]]
title <- snakemake@params[["title"]]
type <- snakemake@params[["type"]]
wrap <- snakemake@params[["wrap"]]
taxrank <- snakemake@params[["taxrank"]]
subset <- snakemake@params[["subset"]]
rank_subset <- snakemake@params[["rank_subset"]]
output <- unlist(snakemake@output)


metagenome <- readRDS(phylo_obj)

bacteria_meta <- subset_taxa(metagenome, Kingdom=='Bacteria')

bacteria_meta_perc <- transform_sample_counts(bacteria_meta, function(x) x*100 / sum(x))

if (subset!=""){
    bacteria_meta_perc <- subset_taxa(bacteria_meta_perc, get(rank_subset) %in% subset)
}

if (plot_rank==""){
    bacteria_meta_perc <- tax_glom(bacteria_meta_perc, taxrank="Species")
} else {
    bacteria_meta_perc <- tax_glom(bacteria_meta_perc, taxrank=taxrank)
}


bacteria_meta_perc.ord <- ordinate(physeq = bacteria_meta_perc, method = method, distance=distance)


png(filename=output, width=640, height=480)

if (wrap==""){
    plot_ordination(bacteria_meta_perc, bacteria_meta_perc.ord, type=type, color=color, title=title, shape=shape)+
            geom_point(size=3)+
            geom_text(aes(label = ifelse(label != "", label, label)), size = 3, vjust = 1.5)

}
else {
    plot_ordination(bacteria_meta_perc, bacteria_meta_perc.ord, type=type, color=color, title=title, shape=shape) +
            facet_wrap(wrap,scales="free_x")+
            geom_point(size=3)+
            geom_text(aes(label = ifelse(label != "", label, label)), size = 3, vjust = 1.5)

}


dev.off()

