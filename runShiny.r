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
    filter(gene %in% plotGenes) %>%
    # convert to long matrix
    tidyr::pivot_longer(cols = !gene,
                 names_to = "Samples",
                 values_to = "Expression") %>%
    # join with metadata to retrieve all metadata information for each row
    left_join(metadata, by = c("Samples" = metadataSampleColumn))
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
                      tableOutput("filteredConverted"),
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
                          selectInput("userGene", "Choose a gene to plot:", choices = c(1,2,3)),
                          
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
                          tabsetPanel(
                            tabPanel(paste0("Across OBTAIN FACTOR 1 FROM DATA/USER")
                                     # the ggplot should be here
                            ),
                            tabPanel(paste0("Across OBTAIN FACTOR 2 FROM DATA/USER")
                                     # the ggplot across factor 2 should be here
                            ),
                            tabPanel("Raw Data Plotted",
                                     plotOutput("singlegene_plot")
                            )
                          )
                          
                        )
                      )
             ),
             
             
             ################################# UI Tab 2: Multi-Gene Analysis #################################
             tabPanel("Multi-Gene Analysis",  # part of navbarPage
                      
                      sidebarLayout(
                        # sidebarPanel should have all the input needed from the user
                        sidebarPanel(
                          tabPanel("Gene Expression"),
                          
                          # drop-down list to type in gene of interest to plot
                          # gene input, change 'choices' to a vector of all rownames of the data matrix
                          selectInput("userGene", "Choose gene(s) to plot:", choices = c(1,2,3)),
                          
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
                            tabPanel(paste0("Across OBTAIN FACTOR 1 FROM DATA/USER")
                                     # the ggplot should be here
                            ),
                            tabPanel(paste0("Across OBTAIN FACTOR 2 FROM DATA/USER")
                                     # the ggplot across factor 2 should be here
                            ),
                            tabPanel("Raw Data Plotted"),
                            plotOutput("multigene_plot")
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
  # reactive functions should be used when an operation is done more than once (e.g reading an input)
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
  # reactive functions should be used when an operation is done more than once (e.g reading an input)
  metadataReader <- reactive({
    # await user input in the relevant fileInput
    metadataFile <- input$inputMetadata
    
    # suppresses error, basically waits for input before it continues render function
    req(metadataFile)
    
    # read the uniquely produced datapath, read the file
    readr::read_delim(metadataFile$datapath, ",", col_names = TRUE, show_col_types = FALSE)
  })
  
  
  # this provides the user factors to chose
  # 'renderUI' dynamically changes by user input (i.e metadata input)
  
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
  
  output$filteredConverted <- renderTable({
    head(filterAndConvert(dataLoader = dataMatReader(),
                          metadataLoader =  metadataReader(),
                          plotGenes = c("Fndc5","Bdnf"),
                          # change conditions to the input of factors from first page
                          conditions = input$chosenFactors))
  })
  
  ################################## Single-Gene Analysis ##################################
  
  data <- reactive({
    req(input$userGene, input$graphType)
    
  })  
  
  output$singlegene_plot <- renderPlot({ 
    g <- ggplot(data(), aes(y = factor, x = gene), fill = gene)+
      geom_boxplot(outlier.shape = 8,outlier.size = 4)+
      theme_minimal()
    
    #save the plot
    #ggsave(filename,device = "png", width = , height = ,)
    #ggsave (filename, device = "pdf",width = , height = ,)
    
    
    
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




