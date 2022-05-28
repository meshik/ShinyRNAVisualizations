#### Libraries ####
library(shiny)
library(tidyr)
library(ggplot2)
library(dplyr)
library(plotly)
library(shinythemes)
library(DT)
library(ggradar)
library(readr)
library(stringr)


## function to convert data to ggplot style ('longer')
filterAndConvert <- function(dataLoader, metadataLoader, plotGenes, conditions){
  ### Produces a matrix with columns of "Gene, Sample, Expression, Conditions1, Condition2, ..." ###
  ### This is a convenient form for plotting with ggplot. ###
  # dataLoader: reactive that loads expression matrix.
  # metadataLoader: reactive that loads metadata matrix.
  # plotGenes: user-inputted genes to plot.
  # conditions: user-inputted conditions of interest.
  
  metadata <- metadataLoader
  metadataSampleColumn <- colnames(metadata)[1]
  # keep only the relevant columns in metadata: sample names and user-chosen conditions/factors
  metadata <- metadata %>%
    dplyr::select(all_of(metadataSampleColumn),
                  all_of(conditions))
  
  convertedData <- dataLoader %>%
    # filter for the user-chosen genes in the plotting tabs
    #TODO: 'gene' here is problematic, it should be a general name/code
    filter(gene %in% plotGenes) %>%
    # convert to long matrix
    tidyr::pivot_longer(cols = !gene,
                        names_to = "Samples",
                        values_to = "Expression") %>%
    # join with metadata to retrieve all metadata information for each row
    inner_join(metadata, by = c("Samples" = metadataSampleColumn))
}


ui <- fluidPage(
  titlePanel("Shiny RNA Visualizations"),
  # name of the whole project - stays at top next to page tabs
  navbarPage(strong("Analyses Tabs:"),
             
             # this sets the entire 'theme'/style
             theme = shinythemes::shinytheme("flatly"),
             
             # main tab: title of the whole page
             tabPanel("Input Data",  # part of navbarPage
                      
                      titlePanel("Input Data"),
                      
                      # accept normalized data:
                      h5("Counts matrix: Rows = Gene names; Columns = Sample names"),
                      fileInput("inputData", "Enter your count-normalized .csv or .xlsx file:", width = '35%'),
                      
                      # accept metadata
                      h5("Metadata: Rows = Sample names; Columns = Related factors (e.g: sex, organ, time...)"),
                      fileInput("inputMetadata", "Enter a metadata .csv or .xlsx file for the counts matrix:", width = '35%'),
                      
                      # present factors from metadata, and let the user choose factors from drop-down to check
                      selectizeInput("chosenFactors",
                                     "Choose all factors you wish to analyze:",
                                     choices = NULL,
                                     multiple = TRUE),
                      
                      # look at head(data), currently for TESTING purposes
                      DT::dataTableOutput("filteredConverted"),
                      tableOutput("dataMatPeek"),
                      tableOutput("metadataMatPeek")
             ),
             
             
             
             ################################# UI Tab 1: Single Gene Analysis #################################
             tabPanel("Single Gene Analysis",  # part of navbarPage
                      
                      sidebarLayout(
                        # sidebarPanel should have all the input needed from the user
                        sidebarPanel(
                          tabPanel("Gene Expression"),
                          
                          # drop-down list to type in gene of interest to plot
                          # gene input, change 'choices' to a vector of all rownames of the data matrix
                          selectizeInput("userGeneSingle", "Choose a gene to plot:",
                                         choices = NULL, selected = "Fndc5"),
                          
                          # input factors
                          #
                          
                          # input Graph type: Boxplot/Violin
                          radioButtons("graphType", "Graph Type",
                                       c("Boxplot" = "boxplot", "Violin" = "violin")),
                          
                          # input scale: linear/log
                          radioButtons("scaleType", "Graph Scale",
                                       c("Linear" = "linear", "Log" = "log")
                                       
                          )
                        ),
                        
                        # mainbarPanel should have the plots
                        mainPanel(
                          tabsetPanel(id = "plotTabSingle",
                            tabPanel(paste0("Across OBTAIN FACTOR 1 FROM DATA/USER"),
                                     value = "factorSingle1",
                                     plotOutput("singlegene_plot1")
                            ),
                            tabPanel(paste0("Across OBTAIN FACTOR 2 FROM DATA/USER"),
                                     value = "factorSingle2",
                                     plotOutput("singlegene_plot2")
                            )
                            
                          )
                          
                        )
                      ),
                      # DT DataTable of plotted data
                      DT::dataTableOutput("singleGeneTable")
             ),
             
             
             ################################# UI Tab 2: Multi-Gene Analysis #################################
             tabPanel("Multi-Gene Analysis",  # part of navbarPage
                      
                      sidebarLayout(
                        # sidebarPanel should have all the input needed from the user
                        sidebarPanel(
                          tabPanel("Gene Expression"),
                          
                          # drop-down list to type in gene of interest to plot
                          # gene input, change 'choices' to a vector of all rownames of the data matrix
                          selectInput("userGeneMulti", "Choose gene(s) to plot:", choices = c(1,2,3)),
                          
                          # input factors
                          
                          
                          # input Graph type: Boxplot/Violin/Scatterplot/RadarCharts
                          radioButtons("graphType", "Graph Type",
                                       c("Scatterplot" = "scatterplot",
                                         "Radar Chart" = "radar chart")),
                          
                          # input scale: linear/log
                          radioButtons("scaleType", "Graph Scale",
                                       c("Linear" = "linear", "Log" = "log"))
                          
                        ), 
                        
                        # mainbarPanel should have the plots
                        mainPanel(
                          tabsetPanel(
                            tabPanel(paste0("Across OBTAIN FACTOR 1 FROM DATA/USER"),
                                     plotOutput("multigene_plot")
                            ),
                            tabPanel(paste0("Across OBTAIN FACTOR 2 FROM DATA/USER")
                                     # the ggplot across factor 2 should be here
                            ),
                            
                          )
                        )
                        
                      )
             ),
             
             
             
             ################################# UI Tab 3: Gene Trajectories #################################
             tabPanel("Trajectories",
                      
                      sidebarLayout(
                        sidebarPanel(
                          # user input list of genes to plot
                          textAreaInput("trajGenes",
                                        "Enter a list of genes seperated by new lines, commas, or spaces:",
                                        value = "Fndc5, Pgc1a\nBdnf, Itgb5"),
                          
                          # add a description under the input area
                          h4("Paste genes of interest")
                        ),
                        
                        # should contain graphs and DT table
                        mainPanel(
                          tabsetPanel(
                            tabPanel("Trajectories Plot",
                                     plotOutput("trajPlot")
                            ),
                            
                            tabPanel("Query Info")
                          )
                          
                        )
                      )
                      
             )
             
  )
)



##################################################################################################################
##################################################### SERVER #####################################################
##################################################################################################################

server <- function(input, output, session){
  
  # change the default limit of 5MB user uploads to 200MB (sample data is 129MB)
  options(shiny.maxRequestSize=200*1024^2)
  
  ################################## Input Tab ##################################
  
  ##### data matrix reader #####
  dataMatReader <- reactive({
    # await user input in the relevant fileInput
    dataFile <- input$inputData
    
    # suppresses error, basically waits for input before it continues render function
    req(dataFile)
    
    # read the uniquely produced datapath, read the file
    #TODO consider looking at the extension to change ',' if needed
    readr::read_delim(dataFile$datapath, ",", col_names = TRUE, show_col_types = FALSE)
  })
  
  ##### metadata #####
  metadataReader <- reactive({
    # await user input in the relevant fileInput
    metadataFile <- input$inputMetadata
    
    # suppresses error, basically waits for input before it continues render function
    req(metadataFile)
    
    # read the uniquely produced datapath, read the file
    metadata <- readr::read_delim(metadataFile$datapath, ",", col_names = TRUE,
                                  show_col_types = FALSE)
    
    # remove problematic characters from colnames
    #TODO: remove all possible interferences, and more elegantly than these multiple calls
    newColnames <- str_replace_all(colnames(metadata), " ", "_") %>%
      str_replace_all(":", "_")
    colnames(metadata) <- newColnames
    
    return(metadata)
  })
  
  
  # this provides the user factors to chose
  observeEvent(
    input$inputMetadata, {
      updateSelectizeInput(session = session, "chosenFactors",
                           "Choose all factors you wish to analyze:",
                           choices = colnames(metadataReader()),
                           server = TRUE)
    })
  
  
  # look at input data
  output$dataMatPeek <- renderTable({
    head(dataMatReader())
  })
  
  # look at input metadata
  output$metadataMatPeek <- renderTable({
    head(metadataReader())
  })
  
  # peek at the plot-ready data with factors by user
  output$filteredConverted <- renderDT({
    plotData <- filterAndConvert(dataLoader = dataMatReader(),
                                 metadataLoader = metadataReader(),
                                 plotGenes = c("Fndc5","Bdnf"),
                                 # change conditions to the input of factors from first page
                                 conditions = input$chosenFactors)
    
    DT::datatable(plotData)
  })
  
  ################################## Single-Gene Analysis ##################################
  
  # updates selection based on input matrix gene names
  observeEvent(
    input$inputData, {
      updateSelectizeInput(session = session, "userGeneSingle", "Choose a gene to plot:",
                           #TODO change $gene to a general call
                           choices = dataMatReader()$gene,
                           server = TRUE)
    })

  data <- reactive({
    req(input$userGene, input$graphType)
    
  })  

  # output$singlegene_plot <- renderPlot({
  #   g <- ggplot(data(), aes(y = factor, x = gene), fill = gene) +
  #     geom_boxplot(outlier.shape = 8, outlier.size = 4) +
  #     theme_minimal()
  # 
  #   #save the plot
  #   #ggsave(filename,device = "png", width = , height = ,)
  #   #ggsave (filename, device = "pdf",width = , height = ,)
  # 
  # 
  # 
  # })
  
  
  ## prepare plot for plotting
  singlegene_plot <- reactive({
    plotData <- filterAndConvert(dataLoader = dataMatReader(),
                                 metadataLoader = metadataReader(),
                                 plotGenes = input$userGeneSingle,
                                 conditions = input$chosenFactors)
    
    # the 2 factors to plot
    #TODO: let the user choose which 2 factors to plot, if they chose more than 2 factors initially
    firstCondition <- input$chosenFactors[1]
    secondCondition <- input$chosenFactors[2]
    
    # dynamically choose the plot variable ordering between tabs
    xAxVar <- switch(input$plotTabSingle,
                     "factorSingle1" = firstCondition,
                     "factorSingle2" = secondCondition)
    facetVar <- switch(input$plotTabSingle,
                       "factorSingle1" = secondCondition,
                       "factorSingle2" = firstCondition)
    
    plotData$facet <- plotData[[facetVar]]
    
    # the full ggplot call
    ggplot(plotData, aes_string(x = xAxVar, y = "Expression",
                                group = xAxVar)) +
      
      # boxplot/violin based on user input
      switch(input$graphType,
             "boxplot" = list(geom_boxplot(aes_string(color = xAxVar), outlier.shape = NA),
                              geom_point(aes_string(alpha = 0.3, size = 5, color = xAxVar),
                                         position = position_jitterdodge())),
             "violin" = geom_violin(aes_string(fill = xAxVar), trim = FALSE)) +
      
      ylab("Expression") +
      xlab(xAxVar) +
      facet_wrap(~facet, ncol = 2) +
      theme(legend.position = "none") +
      
      # y scale based on user input
      switch(input$scaleType, "linear" = scale_y_continuous(), "log" = scale_y_log10())
  })
  
  ## Single Gene Plot
  # funny assignment because shiny (HTML actually) can't handle same named outputs
  output$singlegene_plot1 <- output$singlegene_plot2 <- renderPlot({
    singlegene_plot()
  })
  
  output$singleGeneTable <- renderDT({
    plotData <- filterAndConvert(dataLoader = dataMatReader(),
                                 metadataLoader = metadataReader(),
                                 plotGenes = input$userGeneSingle,
                                 conditions = input$chosenFactors)
    
    DT::datatable(plotData)
  })
  
  ################################## Multi-Gene Analysis ##################################
  
  output$multiGenePlot <- renderPlot({
    g <- ggradar(data (), values.radar = c(0, 0.5, 1),
                 axis.labels = paste0("rownames"),legend.title = "rownames",
                 legend.position = "bottom", background.circle.colour = "white",
                 axis.label.size = 8, group.point.size = 3)
    
    
    
  })
  
  
  
  ################################## Trajectories ##################################
  ## render plots
  output$trajPlot <- renderPlot({
    # transform matrix to z score matrix
    
    ggplot()
    # # load the data matrix
    # plotData <- dataMatReader()
    # ggplot(plotData, aes(x = input$trajGenes, y = )) +
    #   geom_line()
  })
  
  
  ## render interactive DT table
}



##### this connects the two and runs the shiny app #####
shinyApp(ui = ui, server = server)
# 'options = list(display.mode = "showcase")' presents code being run in the server, nice debugging tool..




