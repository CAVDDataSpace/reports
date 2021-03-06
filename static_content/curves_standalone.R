library(optparse)

PLOTSDIR = "/labkey/labkey/files/CAVD/@files/neutralizationCurves"
LOGFILE  = "/labkey/labkey/files/CAVD/@files/curves_log.log"
PLOTFUN  = "/labkey/labkey/files/CAVD/@files/CAVD-DataSpace-Reports/static_content/plot_neutralization_curve.R"

## ----- make option list ------
opt <- list(
    "plotsdir" = PLOTSDIR,
    "plotfuns" = PLOTFUN,
    "logfile" = LOGFILE,
    "labkeyurlbase" = labkey.url.base
    );

## ----- define logger -----
logger <- function(level, msg, ...) {
    cat(format(Sys.time(), "%Y-%m-%d %X"), level, ":", paste(msg, ...), "\n", append = T,
        file = opt$logfile)
}

## -------------------------
logger("INFO", "----- curves.R -----")
logger("INFO", "plotsdir =", opt$plotsdir)
logger("INFO", "plotfuns =", opt$plotfuns)
logger("INFO", "logfile =", opt$logfile)
logger("INFO", "labkeyurlbase =", opt$labkeyurlbase)

## ----- remove all existing plots -----
if(dir.exists(PLOTSDIR)){    
    ul <- unlink(PLOTSDIR, recursive = TRUE)
    logger("INFO", sprintf("Plot directory exists, unlinking %s.", ifelse(ul, "unsuccessful", "successful")))
} else {
    logger("INFO", "Plot directory does not exist")
}

dir.create(PLOTSDIR)

## ----- verify arguments -----
plotsDir <- file.path(opt$plotsdir)

if (!dir.exists(plotsDir)) {
    logger("ERROR:", "could not find ", plotsDir)
    stop("could not find ", plotsDir)
}

if (!file.exists(opt$plotfuns)) {
    logger("ERROR:", "could not find plotfuns")
    stop("could not find plotfuns")
}

if (!file.exists(opt$logfile)) {
    file.create(opt$logfile)
}

## ----- START -----
suppressPackageStartupMessages({
    library(Rlabkey)
    library(data.table)
})

r <- try(source(opt$plotfuns), silent = TRUE)
if ("try-error" %in% class(r)) stop(logger("ERROR", r))

## TODO: Figure out how to pass in credentials on servers
logger("INFO", paste0("pulling data from ", opt$labkeyurlbase))
r <- try({
    labkey.url.base <- opt$labkeyurlbase
    labkey.url.path <- "/CAVD"
    nabmab <- labkey.selectRows(
        baseUrl    = labkey.url.base,
        folderPath = labkey.url.path,
        schemaName = "study",
        queryName  = "NABMAb",
        colNameOpt = "fieldname",
        method     = "GET"
    )
    virIds <- labkey.selectRows(
        baseUrl    = labkey.url.base,
        folderPath = labkey.url.path,
        schemaName = "CDS",
        queryName  = "nabantigen",
        colSelect  = c("virus", "cds_virus_id"),
        colFilter  = makeFilter(c("assay_identifier", "EQUAL", "NAB MAB")),
        colNameOpt = "fieldname",
        method     = "GET"
    )
    nabmab <- merge(nabmab, virIds)
    setDT(nabmab)
    mabs <- unique(nabmab$mab_mix_id)
    viruses <- unique(nabmab$cds_virus_id)
}, silent = TRUE)

if ("try-error" %in% class(r)) stop(logger("ERROR", r))

if (!file.exists(file.path(plotsDir, "axis.png"))) {
    logger("INFO", "Creating axis legend")
    r <- try(createAxisLegend(file.path(plotsDir, "axis.png")), silent = TRUE)
    if ("try-error" %in% class(r)) {
        stop(logger("ERROR", r))
        dev.off()
    }
}

for(paletteName in c("rainbow", "gray")) {

    logger("INFO", paste0("-- ", paletteName, " --"))
    palette <- ifelse(paletteName == "rainbow", MELLOWPAL, GRAY)
    logger("INFO", "plotting mabs vs all viruses")

    ## Mab vs all viruses
    for(mab in mabs){
        te <- try({
            dir <- file.path(plotsDir, paletteName, mab)
            dir.create(dir, recursive = TRUE)
            ## if (!dir.exists(dir)) { dir.create(dir, recursive = TRUE); logger("INFO", "creating", palette,  "dir for", mab) }
            createNeutralizationThumbnail(
                nabmab,
                colorPalette = palette,
                virus_id = NULL,
                mab_id = mab,
                file.path(dir, "all_viruses.png"),
                60
            )
        }, silent = TRUE)
        if ("try-error" %in% class(te)) {
            dev.off()
            logger("WARNING", mab, "vs all viruses failed:", te)
        }
    }

    logger("INFO", "plotting viruses vs all mabs")

    ## Viruses vs all mabs
    r <- try({ dir <- file.path(plotsDir, paletteName, "viruses") }, silent = TRUE)
    if ("try-error" %in% class(r)) {
        stop(logger("ERROR", r))
        dev.off()
    }

    dir.create(dir, recursive = TRUE)
    for(virus in viruses){
        te <- try({
            ## if (!dir.exists(dir)){ dir.create(dir, recursive = TRUE); logger("INFO", "creating", palette, "dir for", virus) }
            createNeutralizationThumbnail(
                nabmab,
                colorPalette = palette,
                virus_id = virus,
                mab_id = NULL,
                file.path(dir, paste0(virus, ".png")),
                60
            )
        }, silent = TRUE)
        if ("try-error" %in% class(te)) {
            dev.off()
            logger("WARNING", virus, "vs all mabs failed:", te)
        }
    }

    logger("INFO", "plotting all combinations of mab vs virus")

    ## Individual
    res_i <- apply(unique(nabmab[mab_mix_id %in% mabs, .(cds_virus_id, mab_mix_id)]), 1,  function(x) {
        c <- try({
            virus <- x[1]
            mab <- x[2]
            dir <- file.path(plotsDir, paletteName, mab)
            ## if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
            createNeutralizationThumbnail(
                nabmab,
                virus,
                mab,
                colorPalette = palette,
                file.path(dir, paste0(virus, ".png")),
                60,
                lineSize = 2,
                pointSize = 1
            )
        }, silent = TRUE)
        if ("try-error" %in% class(c)) {
            dev.off()
            logger("WARNING", x[2], "vs", x[1], "failed:", c)
        }
        return(c)
    })

    logger("INFO", "creating legend")
    r <- try(createLegend(palette = palette, path = file.path(plotsDir, paletteName, "legend.png")), silent = TRUE)
    if ("try-error" %in% class(r)) {
        stop(logger("ERROR", r))
        dev.off()
    }
}

logger("INFO", "Finished curves.R\n")
