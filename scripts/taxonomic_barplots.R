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
tax_ranks <- snakemake@params[["tax_ranks"]]
abund_thres <- snakemake@params[["abundance_threshold"]]
groups <-  snakemake@params[["groups"]]
abundance <- snakemake@params[["abundance"]]
output <- unlist(snakemake@output)
label <- snakemake@params[["label"]]
top_taxa <- snakemake@params[["top_taxa"]]

metagenome <- readRDS(phylo_obj)

bacteria_meta <- subset_taxa(metagenome, Kingdom=='Bacteria')

bacteria_meta_perc <- transform_sample_counts(bacteria_meta, function(x) x*100 / sum(x))

# Explore samples at specific taxonomic levels

tax_plots <- list()

for (tax in tax_ranks) {

    group_plots <- list()

    for (g in groups) {


# Group all the OTUs that have the same taxonomy at a certain taxonomic rank

    if (abundance=="absolut"){
    bacteria_glom <- tax_glom(bacteria_meta, taxrank=tax)
    }
    else {
    bacteria_glom <- tax_glom(bacteria_meta_perc, taxrank=tax)
    }

if (top_taxa!=0){

    f1 <- filterfun_sample(topk(top_taxa))
    wh1 <- genefilter_sample(bacteria_glom,f1,A=2)

}


# Melt phyloseq object into a dataframe to manipulate them with packages like ggplot2 and vegan

    bacteria_glom_df <- psmelt(bacteria_glom)

    str(bacteria_glom_df)

    bacteria_glom_df <- bacteria_glom_df[bacteria_glom_df$Abundance>abund_thres,]

    bacteria_glom_df[[tax]] <- as.factor(bacteria_glom_df[[tax]])


# brewer.pal() is a function from the RColorBrewer package that provides color palettes based on ColorBrewer designs.

    colors <- colorRampPalette(brewer.pal(8,'Dark2'))(length(levels(bacteria_glom_df[[tax]])))

    figure <- ggplot(data=bacteria_glom_df, aes(x=Sample, y=Abundance, fill=get(tax))+
        geom_bar(aes(), stat='identity', position='stack')+
        scale_fill_manual(values = colors)+
        theme(axis.text.x = element_text(angle = 90, vjust = 0.5, hjust=1)) +
        labs(title = paste("Taxonomy barplot on",tax,"level"), fill=tax)+
        facet_wrap(g, scales="free_x")#+
      #geom_text(mapping = aes(label = label), size = 3, vjust = 1.5)



    group_plots[[g]] <- figure

    }

    tax_plots[[tax]] <- group_plots

}


# Save to pdf

for (tax in tax_ranks) {
    tax.pdf <- join(output,paste("taxonomic_barplots",'_',tolower(tax), '.pdf', sep=''))
    pdf(tax.pdf, height=8, width=7)
    for (g in groups){
      plot(tax_plots[[tax]][[g]])
      }
    dev.off()
}