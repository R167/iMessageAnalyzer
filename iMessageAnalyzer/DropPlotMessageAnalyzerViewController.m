//
//  DropPlotMessageAnalyzerViewController.m
//  iMessageAnalyzer
//
//  Created by Ryan D'souza on 11/25/15.
//  Copyright © 2015 Ryan D'souza. All rights reserved.
//

#import "DropPlotMessageAnalyzerViewController.h"

typedef NS_ENUM(NSInteger, Graph_Scale) {
    Graph_Scale_Year,
    Graph_Scale_Month,
    Graph_Scale_Week,
    Graph_Scale_Day,
    Graph_Scale_Hour
};

@interface DropPlotMessageAnalyzerViewController ()

@property (strong, nonatomic) TemporaryDatabaseManager *messageManager;
@property (strong, nonatomic) Person *person;

@property (strong) IBOutlet CPTGraphHostingView *graphHostingView;
@property (strong, nonatomic) CPTXYGraph *graph;

@property (nonatomic, readwrite, assign) double minimumValueForXAxis;
@property (nonatomic, readwrite, assign) double maximumValueForXAxis;
@property (nonatomic, readwrite, assign) double minimumValueForYAxis;
@property (nonatomic, readwrite, assign) double maximumValueForYAxis;
@property (nonatomic, readwrite, assign) double majorIntervalLengthForX;
@property (nonatomic, readwrite, assign) double majorIntervalLengthForY;

@property (nonatomic, readwrite, assign) double totalMaximumYValue;

@property (nonatomic, readwrite, strong) NSArray<NSDictionary *> *dataPoints;

@property (nonatomic, readwrite, strong) CPTPlotSpaceAnnotation *zoomAnnotation;
@property (nonatomic, readwrite, strong) CPTPlotSpace *thisConversationPlot;
@property (nonatomic, readwrite, assign) CGPoint dragStart;
@property (nonatomic, readwrite, assign) CGPoint dragEnd;

@property Graph_Scale currentScale;
@property (strong, nonatomic) NSDate *startDate;
@property (strong, nonatomic) NSDate *endDate;

@property (strong, nonatomic) NSCalendar *calendar;

@end

@implementation DropPlotMessageAnalyzerViewController

- (instancetype) initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil person:(Person *)person temporaryDatabase:(TemporaryDatabaseManager *)temporaryDatabase firstMessageDate:(NSDate *)firstMessage
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    
    if(self) {
        self.messageManager = temporaryDatabase;
        self.person = person;
        
        self.calendar = [NSCalendar currentCalendar];
        [self.calendar setTimeZone:[NSTimeZone systemTimeZone]];
        
        self.dataPoints = [[NSMutableArray alloc] init];
        self.zoomAnnotation = nil;
        self.dragStart = CGPointZero;
        self.dragEnd = CGPointZero;
    }
    
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    CPTXYGraph *graph = [[CPTXYGraph alloc] initWithFrame:self.graphHostingView.frame];
    [graph applyTheme:[CPTTheme themeNamed:kCPTDarkGradientTheme]];
    self.graph = graph;
    self.graphHostingView.hostedGraph = self.graph;
    
    self.graph.paddingLeft   = 0.0;
    self.graph.paddingTop    = 0.0;
    self.graph.paddingRight  = 0.0;
    self.graph.paddingBottom = 0.0;
    
    self.graph.plotAreaFrame.paddingLeft   = 55.0;
    self.graph.plotAreaFrame.paddingTop    = 40.0;
    self.graph.plotAreaFrame.paddingRight  = 40.0;
    self.graph.plotAreaFrame.paddingBottom = 35.0;
    
    self.graph.plotAreaFrame.plotArea.fill = self.graph.plotAreaFrame.fill;
    self.graph.plotAreaFrame.fill          = nil;
    
    self.graph.plotAreaFrame.borderLineStyle = nil;
    self.graph.plotAreaFrame.cornerRadius    = 0.0;
    self.graph.plotAreaFrame.masksToBorder   = NO;
    
    // Setup plot space
    CPTXYPlotSpace *plotSpace = (CPTXYPlotSpace *)self.graph.defaultPlotSpace;
    plotSpace.xRange = [CPTPlotRange plotRangeWithLocation:@(0)
                                                    length:@(366)];
    plotSpace.yRange = [CPTPlotRange plotRangeWithLocation:@(0)
                                                    length:@(100)];
    
    // this allows the plot to respond to mouse events
    [plotSpace setDelegate:self];
    [plotSpace setAllowsUserInteraction:YES];
    
    CPTXYAxisSet *axisSet = (CPTXYAxisSet *)self.graph.axisSet;
    
    CPTXYAxis *x = axisSet.xAxis;
    x.minorTicksPerInterval = 9;
    x.majorIntervalLength = @(self.majorIntervalLengthForX);
    x.labelOffset = 5.0;
    x.axisConstraints = [CPTConstraints constraintWithLowerOffset:0.0];
    
    CPTXYAxis *y = axisSet.yAxis;
    y.minorTicksPerInterval = 9;
    y.majorIntervalLength = @(self.majorIntervalLengthForY);
    y.labelOffset = 5.0;
    y.axisConstraints = [CPTConstraints constraintWithLowerOffset:0.0];
    
    // Create the main plot for the delimited data
    CPTScatterPlot *dataSourceLinePlot = [[CPTScatterPlot alloc] initWithFrame:self.graph.bounds];
    dataSourceLinePlot.identifier = @"Data Source Plot";
    
    CPTMutableLineStyle *lineStyle = [dataSourceLinePlot.dataLineStyle mutableCopy];
    lineStyle.lineWidth              = 1.0;
    lineStyle.lineColor              = [CPTColor whiteColor];
    dataSourceLinePlot.dataLineStyle = lineStyle;
    
    CPTMutableTextStyle *textStyle = [CPTMutableTextStyle textStyle];
    [textStyle setFontSize:8.0f];
    [textStyle setColor:[CPTColor colorWithCGColor:[[NSColor grayColor] CGColor]]];
    
    CPTXYAxis *xAxis = [axisSet xAxis];
    xAxis.labelingPolicy = CPTAxisLabelingPolicyNone;
    [xAxis setMajorIntervalLength:[NSNumber numberWithDouble:30.0]];
    [xAxis setMinorTickLineStyle:nil];
    [xAxis setLabelingPolicy:CPTAxisLabelingPolicyNone];
    [xAxis setLabelTextStyle:textStyle];
    [xAxis setLabelRotation:M_PI/4];
    
    NSMutableArray *tickLocations = [[NSMutableArray alloc] init];
    NSMutableArray *tickLabels = [[NSMutableArray alloc] init];
    for(int i = 0; i < 12; i++) {
        [tickLocations addObject:[NSNumber numberWithInt:30 * i]];
        CPTAxisLabel *label = [[CPTAxisLabel alloc] initWithText:[self MonthNameString:i] textStyle:xAxis.labelTextStyle];
        label.tickLocation = [NSNumber numberWithInt:30 * i + 15];
        label.offset = 1.0f;
        label.rotation = M_PI/3.5f;
        [tickLabels addObject:label];
    }
    
    xAxis.axisLabels = [NSSet setWithArray:tickLabels];
    xAxis.majorTickLocations = [NSSet setWithArray:tickLocations];
    
    dataSourceLinePlot.dataSource = self;
    [self.graph addPlot:dataSourceLinePlot];
    
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void) {
        while(!self.messageManager.finishedAddingEntries) {
            //Do nothing
        }
        //[self getData];
        [self updateData];
        
        dispatch_async(dispatch_get_main_queue(), ^(void) {
            [self.graph reloadData];
            

        });
    });
}

-(NSString*)MonthNameString:(int)monthNumber
{
    NSDateFormatter *formate = [NSDateFormatter new];
    
    NSArray *monthNames = [formate standaloneMonthSymbols];
    
    NSString *monthName = [monthNames objectAtIndex:monthNumber];
    
    return monthName;
}

- (NSArray *)getSubjectTitlesAsArray
{
    NSMutableArray *labelArray = [NSMutableArray array];
    
    CPTMutableTextStyle *textStyle = [CPTMutableTextStyle textStyle];
    [textStyle setFontSize:10];
    
    for (int i = 0; i < 12; i++)
    {
        CPTAxisLabel *axisLabel = [[CPTAxisLabel alloc] initWithText:@"HELLO" textStyle:textStyle];
        [axisLabel setTickLocation:[NSNumber numberWithDouble:(i + 1)]];
        [axisLabel setRotation:M_PI/4];
        [axisLabel setOffset:0.1];
        [labelArray addObject:axisLabel];
    }
    
    return [NSArray arrayWithArray:labelArray];
}

- (void) getData
{
    NSDate *methodStart = [NSDate date];
    
    NSMutableArray *allMessages = [self.messageManager getAllMessagesForPerson:self.person];
    
    NSMutableArray<NSDictionary*> *newData = [[NSMutableArray alloc] init];
    
    const int endTime = (int) [[self getDateAtEndOfYear:[NSDate date]] timeIntervalSinceReferenceDate]; //(int) [[NSDate date] timeIntervalSinceReferenceDate];
    const int timeInterval = 60 * 60;
    
    int startTime = (int) [[self getDateAtBeginningOfYear:[NSDate date]] timeIntervalSinceReferenceDate];
    
    double minX = 0;
    double maxX = 60 * 60 * 365;
    
    double minY = 0;
    double maxY = 0;
    
    int counter = 0;
    int hour = 0;
    
    while(startTime < endTime && counter < allMessages.count) {
        Message *message = allMessages[counter];
        
        //Message occurs after time interval
        if([message.dateSent timeIntervalSinceReferenceDate] > (startTime + timeInterval)) {
            [newData addObject:@{@"x": @(hour), @"y": @(0)}];
        }
        else {
            int numMessages = 0;
            while([message.dateSent timeIntervalSinceReferenceDate] <= (startTime + timeInterval) && counter+1 < allMessages.count) {
                numMessages++;
                counter++;
                message = allMessages[counter];
            }
            
            [newData addObject:@{@"x": @(hour), @"y": @(numMessages)}];
            
            if(numMessages > maxY) {
                maxY = numMessages;
            }
        }
        
        hour++;
        startTime += timeInterval;
        
    }
    
    NSDate *methodFinish = [NSDate date];
    NSTimeInterval executionTime = [methodFinish timeIntervalSinceDate:methodStart];
    NSLog(@"executionTime = %f", executionTime);
    
    self.dataPoints = newData;
    
    self.minimumValueForXAxis = minX;
    self.maximumValueForXAxis = maxX;
    self.minimumValueForYAxis = minY;
    self.maximumValueForYAxis = maxY;
    
    CPTXYPlotSpace *plotSpace = (CPTXYPlotSpace *)self.graph.defaultPlotSpace;
    plotSpace.xRange = [CPTPlotRange plotRangeWithLocation:@(0)
                                                    length:@(maxX)];
    plotSpace.yRange = [CPTPlotRange plotRangeWithLocation:@(0)
                                                    length:@((maxY * 11) / 10)];
    
    self.totalMaximumYValue = maxY;
}

- (void) updateData
{
    double minY = MAXFLOAT;
    double maxY = -MAXFLOAT;
    
    NSMutableArray<NSDictionary*> *newData = [[NSMutableArray alloc] init];
    
    const int endTime = (int) [[self getDateAtEndOfYear:[NSDate date]] timeIntervalSinceReferenceDate]; //(int) [[NSDate date] timeIntervalSinceReferenceDate];
    const int timeInterval = 60 * 60 * 24;
    
    int startTime = (int) [[self getDateAtBeginningOfYear:[NSDate date]] timeIntervalSinceReferenceDate];
    
    double minX = 0;
    double maxX = 0;
    int counter = 0;
    while(startTime < endTime) {
        int tempEndTime = startTime + timeInterval;
        int messageCount = [self.messageManager getConversationMessageCountStartTime:startTime endTime:tempEndTime];
        
        if(messageCount < minY) {
            minY = messageCount;
        }
        
        if(messageCount > maxY) {
            maxY = messageCount;
        }
        
        [newData addObject:@{ @"x": @(counter),
                              @"y": @(messageCount)}];
        
        //NSLog(@"GOT INFO FOR: %@", [self good:[NSDate dateWithTimeIntervalSinceReferenceDate:tempEndTime]]);
        
        startTime += timeInterval;
        counter++;
    }
    
    maxX = counter + 1;
    self.dataPoints = newData;
    
    self.minimumValueForXAxis = minX;
    self.maximumValueForXAxis = maxX;
    self.minimumValueForYAxis = minY;
    self.maximumValueForYAxis = maxY;
    
    CPTXYPlotSpace *plotSpace = (CPTXYPlotSpace *)self.graph.defaultPlotSpace;
    plotSpace.xRange = [CPTPlotRange plotRangeWithLocation:@(0)
                                                    length:@(maxX)];
    plotSpace.yRange = [CPTPlotRange plotRangeWithLocation:@(0)
                                                    length:@((maxY * 11) / 10)];
    
    self.totalMaximumYValue = maxY;
    
    NSLog(@"MAX: %f", maxY);
}

-(IBAction)zoomIn
{
    NSLog(@"ZOOMED IN");
    CPTXYPlotSpace *plotSpace = (CPTXYPlotSpace *)self.graph.defaultPlotSpace;
    CPTPlotArea *plotArea     = self.graph.plotAreaFrame.plotArea;
    
    // convert the dragStart and dragEnd values to plot coordinates
    CGPoint dragStartInPlotArea = [self.graph convertPoint:self.dragStart toLayer:plotArea];
    CGPoint dragEndInPlotArea   = [self.graph convertPoint:self.dragEnd toLayer:plotArea];
    
    double start[2], end[2];
    
    // obtain the datapoints for the drag start and end
    [plotSpace doublePrecisionPlotPoint:start numberOfCoordinates:2 forPlotAreaViewPoint:dragStartInPlotArea];
    [plotSpace doublePrecisionPlotPoint:end numberOfCoordinates:2 forPlotAreaViewPoint:dragEndInPlotArea];
    
    // recalculate the min and max values
    self.minimumValueForXAxis = MIN(start[CPTCoordinateX], end[CPTCoordinateX]);
    self.maximumValueForXAxis = MAX(start[CPTCoordinateX], end[CPTCoordinateX]);
    self.minimumValueForYAxis = MIN(start[CPTCoordinateY], end[CPTCoordinateY]);
    self.maximumValueForYAxis = MAX(start[CPTCoordinateY], end[CPTCoordinateY]);
    
    // now adjust the plot range and axes
    plotSpace.xRange = [CPTPlotRange plotRangeWithLocation:@(self.minimumValueForXAxis)
                                                    length:@(self.maximumValueForXAxis - self.minimumValueForXAxis)];
    plotSpace.yRange = [CPTPlotRange plotRangeWithLocation:@(self.minimumValueForYAxis)
                                                    length:@(self.maximumValueForYAxis - self.minimumValueForYAxis)];
    
    CPTXYAxisSet *axisSet = (CPTXYAxisSet *)self.graph.axisSet;
    //axisSet.xAxis.labelingPolicy = CPTAxisLabelingPolicyAutomatic;
    axisSet.yAxis.labelingPolicy = CPTAxisLabelingPolicyAutomatic;
}


-(IBAction)zoomOut
{
    NSLog(@"ZOOMED OUT");
    double minX = 0;
    double maxX = 366;
    
    double minY = 0;
    
    double intervalX = self.majorIntervalLengthForX;
    double intervalY = self.majorIntervalLengthForY;
    
    minX = floor(minX / intervalX) * intervalX;
    minY = floor(minY / intervalY) * intervalY;
    
    self.minimumValueForXAxis = minX;
    self.maximumValueForXAxis = maxX;
    self.minimumValueForYAxis = minY;
    self.maximumValueForYAxis = (self.totalMaximumYValue * 11) / 10;
    
    // now adjust the plot range and axes
    CPTXYPlotSpace *plotSpace = (CPTXYPlotSpace *)self.graph.defaultPlotSpace;
    
    plotSpace.xRange = [CPTPlotRange plotRangeWithLocation:@(0)
                                                    length:@(maxX)];
    plotSpace.yRange = [CPTPlotRange plotRangeWithLocation:@(0)
                                                    length:@((self.totalMaximumYValue * 11) / 10)];
    CPTXYAxisSet *axisSet = (CPTXYAxisSet *)self.graph.axisSet;
    axisSet.xAxis.labelingPolicy = CPTAxisLabelingPolicyFixedInterval;
    axisSet.yAxis.labelingPolicy = CPTAxisLabelingPolicyFixedInterval;
}

-(NSUInteger)numberOfRecordsForPlot:(CPTPlot *)plot
{
    NSLog(@"SIZE: %d", self.dataPoints.count);
    return self.dataPoints.count;
}

-(id)numberForPlot:(CPTPlot *)plot field:(NSUInteger)fieldEnum recordIndex:(NSUInteger)index
{
    NSString *key = (fieldEnum == CPTScatterPlotFieldX ? @"x" : @"y");
    
    //NSLog(@"%d\t%@\t%@", index, self.dataPoints[index][@"x"], self.dataPoints[index][@"y"]);
    
    //NSLog(@"Also called: %@", self.dataPoints[index][key]);
    return self.dataPoints[index][key];
}

#pragma mark Plot Space Delegate Methods


-(IBAction)exportToPDF:(id)sender
{
    NSSavePanel *pdfSavingDialog = [NSSavePanel savePanel];
    
    [pdfSavingDialog setAllowedFileTypes:@[@"pdf"]];
    
    if ( [pdfSavingDialog runModal] == NSOKButton ) {
        NSData *dataForPDF = [self.graph dataForPDFRepresentationOfLayer];
        
        NSURL *url = [pdfSavingDialog URL];
        if ( url ) {
            [dataForPDF writeToURL:url atomically:NO];
        }
    }
}

-(IBAction)exportToPNG:(id)sender
{
    NSSavePanel *pngSavingDialog = [NSSavePanel savePanel];
    
    [pngSavingDialog setAllowedFileTypes:@[@"png"]];
    
    if ( [pngSavingDialog runModal] == NSOKButton ) {
        NSImage *image            = [self.graph imageOfLayer];
        NSData *tiffData          = [image TIFFRepresentation];
        NSBitmapImageRep *tiffRep = [NSBitmapImageRep imageRepWithData:tiffData];
        NSData *pngData           = [tiffRep representationUsingType:NSPNGFileType properties:[NSDictionary dictionary]];
        
        NSURL *url = [pngSavingDialog URL];
        if ( url ) {
            [pngData writeToURL:url atomically:NO];
        }
    }
}

- (void) plotSpace:(CPTPlotSpace *)space didChangePlotRangeForCoordinate:(CPTCoordinate)coordinate
{
    NSLog(@"CHANGED!!");
}

#pragma mark Plot Space Delegate Methods

-(BOOL)plotSpace:(CPTPlotSpace *)space shouldHandlePointingDeviceDraggedEvent:(id)event atPoint:(CGPoint)interactionPoint
{
    
    NSLog(@"Yo here 4");
    CPTPlotSpaceAnnotation *annotation = self.zoomAnnotation;
    
    if ( annotation ) {
        CPTPlotArea *plotArea = self.graph.plotAreaFrame.plotArea;
        CGRect plotBounds     = plotArea.bounds;
        
        // convert the dragStart and dragEnd values to plot coordinates
        CGPoint dragStartInPlotArea = [self.graph convertPoint:self.dragStart toLayer:plotArea];
        CGPoint dragEndInPlotArea   = [self.graph convertPoint:interactionPoint toLayer:plotArea];
        
        // create the dragrect from dragStart to the current location
        CGFloat endX      = MAX( MIN( dragEndInPlotArea.x, CGRectGetMaxX(plotBounds) ), CGRectGetMinX(plotBounds) );
        CGFloat endY      = MAX( MIN( dragEndInPlotArea.y, CGRectGetMaxY(plotBounds) ), CGRectGetMinY(plotBounds) );
        CGRect borderRect = CGRectMake( dragStartInPlotArea.x, dragStartInPlotArea.y,
                                       (endX - dragStartInPlotArea.x),
                                       (endY - dragStartInPlotArea.y) );
        
        annotation.contentAnchorPoint = CGPointMake(dragEndInPlotArea.x >= dragStartInPlotArea.x ? 0.0 : 1.0,
                                                    dragEndInPlotArea.y >= dragStartInPlotArea.y ? 0.0 : 1.0);
        annotation.contentLayer.frame = borderRect;
    }
    
    return NO;
}

-(BOOL)plotSpace:(CPTPlotSpace *)space shouldHandlePointingDeviceDownEvent:(id)event atPoint:(CGPoint)interactionPoint
{
    
    NSLog(@"Yo here 3");
    if ( !self.zoomAnnotation ) {
        self.dragStart = interactionPoint;
        
        CPTPlotArea *plotArea       = self.graph.plotAreaFrame.plotArea;
        CGPoint dragStartInPlotArea = [self.graph convertPoint:self.dragStart toLayer:plotArea];
        
        if ( CGRectContainsPoint(plotArea.bounds, dragStartInPlotArea) ) {
            // create the zoom rectangle
            // first a bordered layer to draw the zoomrect
            CPTBorderedLayer *zoomRectangleLayer = [[CPTBorderedLayer alloc] initWithFrame:CGRectNull];
            
            CPTMutableLineStyle *lineStyle = [CPTMutableLineStyle lineStyle];
            lineStyle.lineColor                = [CPTColor darkGrayColor];
            lineStyle.lineWidth                = 1.0;
            zoomRectangleLayer.borderLineStyle = lineStyle;
            
            CPTColor *transparentFillColor = [[CPTColor blueColor] colorWithAlphaComponent:0.2];
            zoomRectangleLayer.fill = [CPTFill fillWithColor:transparentFillColor];
            
            double start[2];
            [self.graph.defaultPlotSpace doublePrecisionPlotPoint:start numberOfCoordinates:2 forPlotAreaViewPoint:dragStartInPlotArea];
            CPTNumberArray anchorPoint = @[@(start[CPTCoordinateX]),
                                           @(start[CPTCoordinateY])];
            
            // now create the annotation
            CPTPlotSpace *defaultSpace = self.graph.defaultPlotSpace;
            if ( defaultSpace ) {
                CPTPlotSpaceAnnotation *annotation = [[CPTPlotSpaceAnnotation alloc] initWithPlotSpace:defaultSpace anchorPlotPoint:anchorPoint];
                annotation.contentLayer = zoomRectangleLayer;
                self.zoomAnnotation     = annotation;
                
                [self.graph.plotAreaFrame.plotArea addAnnotation:annotation];
            }
        }
    }
    
    return NO;
}

-(BOOL)plotSpace:(CPTPlotSpace *)space shouldHandlePointingDeviceUpEvent:(id)event atPoint:(CGPoint)interactionPoint
{
    NSLog(@"Yo here 1");
    CPTPlotSpaceAnnotation *annotation = self.zoomAnnotation;
    
    if ( annotation ) {
        self.dragEnd = interactionPoint;
        
        // double-click to completely zoom out
        if ( [event clickCount] == 2 ) {
            CPTPlotArea *plotArea     = self.graph.plotAreaFrame.plotArea;
            CGPoint dragEndInPlotArea = [self.graph convertPoint:interactionPoint toLayer:plotArea];
            
            if ( CGRectContainsPoint(plotArea.bounds, dragEndInPlotArea) ) {
                [self zoomOut];
            }
        }
        else if ( !CGPointEqualToPoint(self.dragStart, self.dragEnd) ) {
            // no accidental drag, so zoom in
            [self zoomIn];
        }
        
        // and we're done with the drag
        [self.graph.plotAreaFrame.plotArea removeAnnotation:annotation];
        self.zoomAnnotation = nil;
        
        self.dragStart = CGPointZero;
        self.dragEnd   = CGPointZero;
    }
    
    return NO;
}

-(BOOL)plotSpace:(CPTPlotSpace *)space shouldHandlePointingDeviceCancelledEvent:(id)event atPoint:(CGPoint)interactionPoint
{
    
    NSLog(@"Yo here 2");
    CPTPlotSpaceAnnotation *annotation = self.zoomAnnotation;
    
    if ( annotation ) {
        [self.graph.plotAreaFrame.plotArea removeAnnotation:annotation];
        self.zoomAnnotation = nil;
        
        self.dragStart = CGPointZero;
        self.dragEnd   = CGPointZero;
    }
    
    return NO;
}

- (NSDate*) getDateAtEndOfYear:(NSDate*)inputDate
{
    // Selectively convert the date components (year, month, day) of the input date
    NSDateComponents *dateComps = [self.calendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:inputDate];
    
    [dateComps setHour:23];
    [dateComps setMinute:59];
    [dateComps setSecond:59];
    [dateComps setMonth:12];
    [dateComps setDay:31];
    
    // Convert back
    NSDate *beginningOfDay = [self.calendar dateFromComponents:dateComps];
    return beginningOfDay;
}


- (NSDate*) getDateAtBeginningOfYear:(NSDate*)inputDate
{
    // Selectively convert the date components (year, month, day) of the input date
    NSDateComponents *dateComps = [self.calendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:inputDate];
    
    [dateComps setHour:0];
    [dateComps setMinute:0];
    [dateComps setSecond:1];
    [dateComps setMonth:1];
    [dateComps setDay:1];
    
    // Convert back
    NSDate *beginningOfDay = [self.calendar dateFromComponents:dateComps];
    return beginningOfDay;
}

- (long)timeAtBeginningOfDayForDate:(NSDate*)inputDate
{
    // Selectively convert the date components (year, month, day) of the input date
    NSDateComponents *dateComps = [self.calendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:inputDate];
    
    // Set the time components manually
    [dateComps setHour:0];
    [dateComps setMinute:0];
    [dateComps setSecond:1];
    
    // Convert back
    NSDate *beginningOfDay = [self.calendar dateFromComponents:dateComps];
    return [beginningOfDay timeIntervalSinceReferenceDate];
}

@end