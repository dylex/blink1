//
//  B1SAppDelegate.m
//  Blink1Control
//
//  Created by Tod E. Kurt on 8/31/12.
//  Copyright (c) 2012 ThingM. All rights reserved.
//
//
// ToDo:
// - network real-time load input
//
// inputs have attributes
// - enabled  -- boolean,
// - iname    -- string, name of input
// - type     -- string, type of input ("url","file","ifttt")
// - arg      -- string, argument for type of input (url, filepath)
// - pname    -- string, name of pattern to play (if none specified in content of input, like file)
// - status   -- string, last status of input
// - lastVal  -- string, last value when input was parsed
// - lastTime -- date?, last time when input was parsed
//

#import "B1SAppDelegate.h"
#import "RoutingHTTPServer.h"


@interface B1SAppDelegate ()

@end


@implementation B1SAppDelegate

@synthesize window = _window;
@synthesize webView = _webView;
@synthesize blink1status = _blink1status;
@synthesize blink1serial = _blink1serial;

@synthesize statusItem;
@synthesize statusMenu;
@synthesize statusImage;
//@synthesize statusHighlightImage;

@synthesize http;
@synthesize blink1;


//FIXME: what to do with these URLs?
NSString* confURL =  @"http://127.0.0.1:8080/blink_1/";
NSString* playURL =  @"http://127.0.0.1:8080/bootstrap/blink1.html";
NSString* iftttEventUrl = @"http://api.thingm.com/blink1/events";


// play pattern with restart
// pname might also be just a hex color, e.g. "#FF0033"
- (void) playPattern: (NSString*)pname
{
    [self playPattern:pname restart:true];
}

// play a pattern
// can restart if already playing, or just leave be an already playing pattern
- (void) playPattern: (NSString*)pname restart:(Boolean)restart
{
    if( pname == nil ) return;
    if( [pname hasPrefix:@"#"] ) { // a hex color, not a proper pattern
        [blink1 fadeToRGB:[Blink1 colorFromHexRGB:pname] atTime:0.1];
        return;
    }

    Blink1Pattern* pattern = [patterns objectForKey:pname];
    if( pattern != nil ) {
        [pattern setBlink1:blink1];  // FIXME: just in case
        if( ![pattern playing] || ([pattern playing] && restart) ) {
            [pattern play];
        }
    }
}

// stop a currently playing pattern
- (void) stopPattern: (NSString*)pname
{
    if( pname == nil ) return;
    Blink1Pattern* pattern = [patterns objectForKey:pname];
    [pattern stop];
}

- (void) stopAllPatterns
{
    for( Blink1Pattern* pattern in [patterns allValues] ) {
        [pattern stop];
    }
}

//
// Given a string (contents of file or url),
// analyze it for a pattern name or rgb hex string
// returns pattern to play, or nil if nothing to play
//
- (NSString*) parsePatternOrColorInString: (NSString*) str
{
    DLog(@"parsePatternOrColorInString: %@",str);
    NSString* patternstr = [self readColorPattern:str];
    NSString* patt = nil;

    if( patternstr ) {  // pattern detected
        DLog(@"found color pattern: %@",patternstr);
        patt = patternstr;
    }
    else  {
        NSColor* colr = [Blink1 colorFromHexRGB:str];
        if( colr ) {
            // TODO: create and play pattern from hex color, like "1,#FF33CC,0.1"
            // BUT: maybe make a 'temp' pattern? or a special class of pattern? or a parameterized meta-pattern?
            // let's try: FIXME: hack using "-1" to mean "temporary pattern"
            //patt = [NSString stringWithFormat:@"-1,%@,0.1",[Blink1 hexStringFromColor:colr]];
            patt = [Blink1 hexStringFromColor:colr];
            DLog(@"hex color patt: %@",patt);
        }
        else {
            DLog(@"no color found");
        }
    }
    return patt;
}

//
// Search for 'pattern: "pattern name"' in contentStr
// contentStr can also be JSON
// returns pattern name if successful, or 'nil' if no pattern found
//
- (NSString*) readColorPattern: (NSString*)contentStr
{
    NSString* str = nil;
    NSScanner *scanner = [NSScanner scannerWithString:contentStr];
    BOOL isPattern = [scanner scanUpToString:@"pattern" intoString:NULL];
    if( isPattern || (!isPattern && str==nil) ) { // match or at begining of string
        [scanner scanString:@"pattern" intoString:NULL]; // consume 'pattern'
        [scanner scanUpToString:@":" intoString:NULL];   // read colon
        [scanner scanString:@":" intoString:NULL];       // consume colon
        [scanner scanUpToString:@"\"" intoString:NULL];  // read open quote
        [scanner scanString:@"\"" intoString:NULL];      // consume open quote
        [scanner scanUpToString:@"\"" intoString:&str];  // read string
    }
    return str;
}

//
- (NSString*) getContentsOfUrl: (NSString*) urlstr
{
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:urlstr]];
    NSData *response = [NSURLConnection sendSynchronousRequest:request returningResponse:nil error:nil];
    NSString *responseStr = [[NSString alloc] initWithData:response encoding:NSUTF8StringEncoding];
    return responseStr;
}

// for "watchfile" functionality, should be put in its own class
- (void)updateWatchFile:(NSString*)wPath
{
    DLog(@"updateWatchFile %@",wPath);
    BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:wPath];
    if( !fileExists ) { // if no file, make one to watch, with dummy content
        NSString *content = @"Put this in a file please.";
        NSData *fileContents = [content dataUsingEncoding:NSUTF8StringEncoding];
        [[NSFileManager defaultManager] createFileAtPath:wPath
                                                contents:fileContents
                                              attributes:nil];
    }

    if( myVDKQ != nil ) [myVDKQ removePath:wPath];
    [myVDKQ addPath:wPath];
    watchFileChanged = true;
}

// for "watchfile" functionality, should be put in its own class
-(void) VDKQueue:(VDKQueue *)queue receivedNotification:(NSString*)noteName forPath:(NSString*)fpath;
{
    DLog(@"watch file: %@ %@", noteName, fpath);
    if( [noteName isEqualToString:@"VDKQueueFileWrittenToNotification"] ) {
        DLog(@"watcher: file written %@ %@", noteName, fpath);
        watchFileChanged = true;
    }
    // FIXME: this doesn't work
    if( [noteName isEqualToString:@"VDKQueueLinkCountChangedNotification"]) {
        DLog(@"re-adding deleted file");
        [self updateWatchFile:fpath];
    }
}


//
- (Boolean) deleteInput: (NSString*)iname
{
    NSDictionary *input = [inputs objectForKey:iname];
    if( input == nil ) return false;
    
    NSString* type = [input objectForKey:@"type"];
    NSString* arg = [input objectForKey:@"arg"];
    if( [type isEqualToString:@"file"] ) {
        DLog(@"remove path %@",arg);
        [myVDKQ removePath:arg];
    }
    else if( [type isEqualToString:@"url"] ) {
        DLog(@"remove url %@",arg);
    }
    [inputs removeObjectForKey:iname];
    return true;
}

// ----------------------------------------------------------------------------
// the main deal for triggering color patterns
// ----------------------------------------------------------------------------
- (void) updateInputs
{
    DLog(@"updateInputs");
    if( !inputsEnable ) return;
    
    int cpuload = [cpuuse getCPUuse];
    
    NSString* key;
    for( key in inputs) {
        NSMutableDictionary* input = [inputs objectForKey:key];
        NSString* type    = [input valueForKey:@"type"];
        NSString* arg     = [input valueForKey:@"arg"];
        NSString* lastVal = [input valueForKey:@"lastVal"];
        
        if( [type isEqualToString:@"url"])
        {
            NSString* responsestr = [self getContentsOfUrl: arg];
            NSString* patternstr  = [self parsePatternOrColorInString: responsestr];
            
            if( patternstr!=nil && ![patternstr isEqualToString:lastVal] ){ // different!
                DLog(@"playing pattern %@",patternstr);
                [self playPattern: patternstr]; // FIXME: need to check for no pattern?
                [input setObject:patternstr forKey:@"lastVal"]; // save last val
            } else {
                DLog(@"no change");
            }
        }
        else if( [type isEqualToString:@"file"] )
        {
            // this is done using FSEvents
        }
        else if( [type isEqualToString:@"ifttt"] )
        {
            NSString* eventUrlStr = [NSString stringWithFormat:@"%@/%@", iftttEventUrl, [blink1 blink1_id]];
            
            NSString* jsonStr = [self getContentsOfUrl: eventUrlStr];
            DLog(@"got string: %@",jsonStr);
            id object = [_jsonparser objectWithString:jsonStr];
            NSDictionary* list = [(NSDictionary*)object objectForKey:@"events"];
            for (NSDictionary *event in list) {
                NSString * bl1_id     = [event objectForKey:@"blink1_id"];
                NSString * bl1_name   = [event objectForKey:@"name"];
                NSString * bl1_source = [event objectForKey:@"source"];
                DLog(@"bl1_id:%@, name:%@, source:%@", bl1_id, bl1_name, bl1_source);

                NSString* patternstr = [self parsePatternOrColorInString: bl1_name]; //FIXME: source?
                [self playPattern: patternstr];
            }
        }
        else if( [type isEqualToString:@"cpuload"] )
        {
            int level = [arg intValue];
            DLog(@"cpuload:%d%% - level:%d",cpuload,level);
            if( cpuload >= level ) {
                [self playPattern: [input valueForKey:@"pname"] restart:NO];
            }
        }
        else if( [type isEqualToString:@"netload"] )
        {
            
        }
    } //for(key)
}



//
- (void) loadPrefs
{
    inputs   = [[NSMutableDictionary alloc] init];
    patterns = [[NSMutableDictionary alloc] init];

    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    NSDictionary *inputspref  = [prefs dictionaryForKey:@"inputs"];
    NSData *patternspref      = [prefs objectForKey:@"patterns"];
    NSString* blink1_id_prefs = [prefs stringForKey:@"blink1_id"];
    NSString* host_id_prefs   = [prefs stringForKey:@"host_id"];
    //BOOL first_run            = [prefs boolForKey:@"first_run"];
    
    if( inputspref != nil ) {
        [inputs addEntriesFromDictionary:inputspref];
    }
    if( patternspref != nil ) {
        patterns = [NSKeyedUnarchiver unarchiveObjectWithData:patternspref];
        //for( Blink1Pattern* pattern in [patterns allValues] ) {
        //    [pattern setBlink1:blink1];
        //}
    }

    [blink1 setHost_id:host_id_prefs]; // accepts nil
    if( blink1_id_prefs != nil ) {
        [blink1 setBlink1_id:blink1_id_prefs];
    } else {
        [blink1 regenerateBlink1Id];
    }
    DLog(@"blink1_id:%@",[blink1 blink1_id]);
    
    //if( !first_run ) {
    //}
}

//
- (void) savePrefs
{
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    [prefs setObject:inputs forKey:@"inputs"];
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:patterns];
    [prefs setObject:data forKey:@"patterns"];
    [prefs setObject:[blink1 blink1_id] forKey:@"blink1_id"];
    [prefs setObject:[blink1 host_id]   forKey:@"host_id"];
    [prefs synchronize];
}

// ----------------------------------------------------------------------------
// Start
// ----------------------------------------------------------------------------
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    srand([[NSDate date]  timeIntervalSince1970]);

    blink1 = [[Blink1 alloc] init];      // set up blink(1) library
    [blink1 enumerate];
    
    __weak id weakSelf = self; // FIXME: hmm, http://stackoverflow.com/questions/4352561/retain-cycle-on-self-with-blocks
    blink1.updateHandler = ^(NSColor *lastColor, float lastTime) {
        NSString* lastcolorstr = [Blink1 hexStringFromColor:lastColor];
        [[weakSelf window] setTitle:[NSString stringWithFormat:@"blink(1) control - %@",lastcolorstr]];
    };
     
    // set up json parser
    _jsonparser = [[SBJsonParser alloc] init];
    _jsonwriter = [[SBJsonWriter alloc] init];
    _jsonwriter.humanReadable = YES;
    _jsonwriter.sortKeys = YES;

    [self loadPrefs];
    
    [self setupHttpServer];
    
    // set up file watcher
    myVDKQ = [[VDKQueue alloc] init];
    [myVDKQ setDelegate:self];
    [self updateWatchFile:@"/Users/tod/tmp/blink1-colors.txt"];  //FIXME: test
    
    // set up input watcher
    float timersecs = 5.0;
    inputsTimer = [NSTimer timerWithTimeInterval:timersecs target:self selector:@selector(updateInputs) userInfo:nil repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:inputsTimer forMode:NSRunLoopCommonModes];

    inputsEnable = true;
    
    // set up cpu use measurement tool
    cpuuse = [[CPUuse alloc] init];
    [cpuuse setup]; // FIXME: how to put stuff in init

    [self updateUI];  // FIXME: right way to do this?

    [self openConfig:nil]; //
}


// set up local http server
- (void)setupHttpServer
{
    self.http = [[RoutingHTTPServer alloc] init];
    
	// Set a default Server header in the form of YourApp/1.0
	NSDictionary *bundleInfo = [[NSBundle mainBundle] infoDictionary];
	NSString *appVersion = [bundleInfo objectForKey:@"CFBundleShortVersionString"];
	if (!appVersion) appVersion = [bundleInfo objectForKey:@"CFBundleVersion"];

	NSString *serverHeader = [NSString stringWithFormat:@"%@/%@",
							  [bundleInfo objectForKey:@"CFBundleName"],
							  appVersion];
	[http setDefaultHeader:@"Server" value:serverHeader];
    
    [self setupHttpRoutes];
    
	// Server on port 8080 serving files from our embedded Web folder
	[http setPort:8080];
	NSString *htmlPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"html"];
	[http setDocumentRoot:htmlPath];
    DLog(@"htmlPath: %@",htmlPath);
    
	NSError *error;
	if (![http start:&error]) {
		DLog(@"Error starting HTTP server: %@", error);
	}

}

//-----------------------------------------------------------------------------
// Local HTTP server routes
// ----------------------------------------------------------------------------
- (void)setupHttpRoutes
{
	[http get:@"/blink1" withBlock:^(RouteRequest *request, RouteResponse *response) {
        NSMutableDictionary *respdict = [[NSMutableDictionary alloc] init];
        [respdict setObject:[blink1 serialnums] forKey:@"blink1_serialnums"];
        [respdict setObject:[blink1 blink1_id]  forKey:@"blink1_id"];
        [respdict setObject:@"blink1" forKey:@"status"];
        [response respondWithString: [_jsonwriter stringWithObject:respdict]];
	}];
    
    [http get:@"/blink1/id" withBlock:^(RouteRequest *request, RouteResponse *response) {
        NSMutableDictionary *respdict = [[NSMutableDictionary alloc] init];
        [respdict setObject:[blink1 serialnums] forKey:@"blink1_serialnums"];
        [respdict setObject:[blink1 blink1_id]  forKey:@"blink1_id"];
        [respdict setObject:@"id" forKey:@"status"];
        [response respondWithString: [_jsonwriter stringWithObject:respdict]];
    }];

    [http get:@"/blink1/regenerateblink1id" withBlock:^(RouteRequest *request, RouteResponse *response) {
        NSString* blink1_id_old = [blink1 blink1_id];
        [blink1 setHost_id:nil];
        NSString* blink1_id = [blink1 regenerateBlink1Id];
        NSMutableDictionary *respdict = [[NSMutableDictionary alloc] init];
        [respdict setObject:blink1_id_old  forKey:@"blink1_id_old"];
        [respdict setObject:blink1_id      forKey:@"blink1_id"];
        [respdict setObject:@"regenerateblink1id" forKey:@"status"];
        [response respondWithString: [_jsonwriter stringWithObject:respdict]];
    }];
    
    [http get:@"/blink1/enumerate" withBlock:^(RouteRequest *request, RouteResponse *response) {
        
        NSString* blink1_id_old = [blink1 blink1_id];
        
        [blink1 enumerate];
        [blink1 regenerateBlink1Id];
        
        NSMutableDictionary *respdict = [[NSMutableDictionary alloc] init];
        [respdict setObject:[blink1 serialnums]  forKey:@"blink1_serialnums"];
        [respdict setObject:blink1_id_old        forKey:@"blink1_id_old"];
        [respdict setObject:[blink1 blink1_id]   forKey:@"blink1_id"];
        [respdict setObject:@"enumerate"         forKey:@"status"];
        [response respondWithString: [_jsonwriter stringWithObject:respdict]];
    }];

    [http get:@"/blink1/fadeToRGB" withBlock:^(RouteRequest *request, RouteResponse *response) {
        [self stopPattern:@"all"];
        NSString* rgbstr = [request param:@"rgb"];
        NSString* timestr = [request param:@"time"];
        if( rgbstr==nil ) rgbstr = @"";
        if( timestr==nil ) timestr = @"";
        NSColor * colr = [Blink1 colorFromHexRGB: rgbstr];
        float secs = 0.1;
        [[NSScanner scannerWithString:timestr] scanFloat:&secs];

        [blink1 fadeToRGB:colr atTime:secs];

        NSString* statusstr = [NSString stringWithFormat:@"fadeToRGB: %@ t:%2.3f",[Blink1 hexStringFromColor:colr],secs];
        NSMutableDictionary *respdict = [[NSMutableDictionary alloc] init];
        [respdict setObject:rgbstr forKey:@"rgb"];
        [respdict setObject:[NSString stringWithFormat:@"%2.3f",secs] forKey:@"time"];
        [respdict setObject:statusstr forKey:@"status"];
		[response respondWithString: [_jsonwriter stringWithObject:respdict]];
	}];

    [http get:@"/blink1/off" withBlock:^(RouteRequest *request, RouteResponse *response) {
        [self stopPattern:@"all"];
        [blink1 fadeToRGB:[Blink1 colorFromHexRGB: @"#000000"] atTime:0.1];

        NSMutableDictionary *respdict = [[NSMutableDictionary alloc] init];
        [respdict setObject:@"off" forKey:@"status"];
        [response respondWithString: [_jsonwriter stringWithObject:respdict]];
    }];

    [http get:@"/blink1/on" withBlock:^(RouteRequest *request, RouteResponse *response) {
        [self stopPattern:@"all"];
        [blink1 fadeToRGB:[Blink1 colorFromHexRGB: @"#FFFFFF"] atTime:0.1];

        NSMutableDictionary *respdict = [[NSMutableDictionary alloc] init];
        [respdict setObject:@"on" forKey:@"status"];
        [response respondWithString: [_jsonwriter stringWithObject:respdict]];
    }];

    [http get:@"/blink1/lastColor" withBlock:^(RouteRequest *request, RouteResponse *response) {
        NSMutableDictionary *respdict = [[NSMutableDictionary alloc] init];
        [respdict setObject:[blink1 lastColorHexString] forKey:@"lastColor"];
        [respdict setObject:@"lastColor" forKey:@"status"];
        [response respondWithString: [_jsonwriter stringWithObject:respdict]];
    }];

    
    // color patterns
    
    // list patterns
    [http get:@"/blink1/pattern" withBlock:^(RouteRequest *request, RouteResponse *response) {
        NSMutableDictionary *respdict = [[NSMutableDictionary alloc] init];//[NSMutableDictionary dictionaryWithDictionary:patterns];
        [respdict setObject:@"pattern results" forKey:@"status"];
        [respdict setObject:[patterns allValues] forKey:@"patterns"];
		[response respondWithString: [_jsonwriter stringWithObject:respdict]];
    }];
    
    // add a pattern
    [http get:@"/blink1/pattern/add" withBlock:^(RouteRequest *request, RouteResponse *response) {
        NSString* pname      = [request param:@"pname"];
        NSString* patternstr = [request param:@"pattern"];
        Blink1Pattern* pattern = nil;
        NSString* statusstr = @"pattern add";
        
        if( pname != nil && patternstr != nil ) {
            pattern = [[Blink1Pattern alloc] initWithPatternString:patternstr name:pname];
            [patterns setObject:pattern forKey:pname];
        }
        else {
            statusstr = @"error: need 'pname' and 'pattern' arguments to make pattern";
        }
        
        NSMutableDictionary *respdict = [[NSMutableDictionary alloc] init];
        if( pattern!=nil)
            [respdict setObject:pattern forKey:@"pattern"];
        [respdict setObject:statusstr forKey:@"status"];
        [response respondWithString: [_jsonwriter stringWithObject:respdict]];
        [self savePrefs];
    }];
    
    // delete a pattern
    [http get:@"/blink1/pattern/del" withBlock:^(RouteRequest *request, RouteResponse *response) {
        NSString* pname   = [request param:@"pname"];
        NSString* statusstr = @"must specify a 'pname' pattern name";
        if( pname != nil ) {
            Blink1Pattern* pattern = [patterns objectForKey:pname];
            if( pattern != nil ) {
                [patterns removeObjectForKey:pname];
                statusstr = [NSString stringWithFormat:@"pattern %@ removed", pname];
            } else {
                statusstr = @"no such pattern";
            }
        }
        else {
            pname = @"";
        }

        NSMutableDictionary *respdict = [[NSMutableDictionary alloc] init];
        [respdict setObject:pname forKey:@"pname"];
        [respdict setObject:statusstr forKey:@"status"];
		[response respondWithString: [_jsonwriter stringWithObject:respdict]];
        [self savePrefs];
    }];
    
    // delete all patterns
    [http get:@"/blink1/pattern/delall" withBlock:^(RouteRequest *request, RouteResponse *response) {
        for( NSString* pname in [patterns allKeys] ) {
            [patterns removeObjectForKey:pname];
        }
        NSMutableDictionary *respdict = [[NSMutableDictionary alloc] init];
        [respdict setObject:@"delall" forKey:@"status"];
		[response respondWithString: [_jsonwriter stringWithObject:respdict]];
        [self savePrefs];
    }];
    
    // play a pattern
    [http get:@"/blink1/pattern/play" withBlock:^(RouteRequest *request, RouteResponse *response) {
        NSString* pname   = [request param:@"pname"];
        [self playPattern: pname];
        //if( pname != nil ) {
        //}
        NSMutableDictionary *respdict = [[NSMutableDictionary alloc] init];
        [respdict setObject:@"pattern play" forKey:@"status"];
		[response respondWithString: [_jsonwriter stringWithObject:respdict]];
    }];

    // stop a pattern
    [http get:@"/blink1/pattern/stop" withBlock:^(RouteRequest *request, RouteResponse *response) {
        NSString* pname   = [request param:@"pname"];
        if( [pname isEqualToString:@"all"] )
            [self stopAllPatterns];
        else
            [self stopPattern:pname];
        
        NSMutableDictionary *respdict = [[NSMutableDictionary alloc] init];
        [respdict setObject:@"stop" forKey:@"status"];
		[response respondWithString: [_jsonwriter stringWithObject:respdict]];
    }];

    
    // inputs
    
    // list all inputs
    [http get:@"/blink1/input" withBlock:^(RouteRequest *request, RouteResponse *response) {
        NSString* enable = [request param:@"enable"];
        if( enable != nil ) {   // i.e. param was specified
            inputsEnable = ([enable isEqualToString:@"on"] || [enable isEqualToString:@"true"] );
        }

        NSString* statusstr = @"input results";
        NSMutableDictionary *respdict = [[NSMutableDictionary alloc] init];
        [respdict setObject:[inputs allValues] forKey:@"inputs"];
        [respdict setObject:statusstr forKey:@"status"];
        [respdict setObject:[NSNumber numberWithBool:inputsEnable] forKey:@"enabled"];
		[response respondWithString: [_jsonwriter stringWithObject:respdict]];
    }];
    
    // delete an input
    [http get:@"/blink1/input/del" withBlock:^(RouteRequest *request, RouteResponse *response) {
        NSString* iname = [request param:@"iname"];
        
        NSString* statusstr = @"no such input";
        if( iname != nil ) {
            if( [self deleteInput:iname] ) {
                statusstr = @"input removed";
            }
        }
        
        NSMutableDictionary *respdict = [[NSMutableDictionary alloc] init];
        [respdict setObject:statusstr forKey:@"status"];
		[response respondWithString: [_jsonwriter stringWithObject:respdict]];
        [self savePrefs];
    }];
    
    // delete all inputs
    [http get:@"/blink1/input/delall" withBlock:^(RouteRequest *request, RouteResponse *response) {
        for( NSString* iname in [inputs allKeys]){
            [self deleteInput:iname];
        }
        NSMutableDictionary *respdict = [[NSMutableDictionary alloc] init];
        [respdict setObject:@"delall" forKey:@"status"];
		[response respondWithString: [_jsonwriter stringWithObject:respdict]];
        [self savePrefs];
    }];
        
    // add a file watching input -- FIXME: needs work
    [http get:@"/blink1/input/file" withBlock:^(RouteRequest *request, RouteResponse *response) {
        NSString* iname = [request param:@"iname"];
        NSString* path  = [request param:@"path"];
        
        NSMutableDictionary* input = [[NSMutableDictionary alloc] init];

        if( iname != nil && path != nil ) {
            NSString* fpath = [path stringByExpandingTildeInPath];
            [input setObject:iname   forKey:@"iname"];
            [input setObject:@"file" forKey:@"type"];
            [input setObject:fpath   forKey:@"arg"];
            [inputs setObject:input  forKey:iname];  // add new input to inputs list
            
            [self performSelectorOnMainThread:@selector(updateWatchFile:)
                                   withObject:fpath
                                waitUntilDone:NO];

            DLog(@"watching file %@",fpath);
        }
        else {
            //path = watchPath;
        }
        
        NSString* filecontents = @"";
        if( watchFileChanged ) {
            filecontents = [NSString stringWithContentsOfFile:path
                                                     encoding:NSUTF8StringEncoding error:nil];
            watchFileChanged = false;
        }

        NSMutableDictionary *respdict = [NSMutableDictionary dictionaryWithDictionary:input];
        [respdict setObject:filecontents  forKey:@"new_event"];
        [respdict setObject:input         forKey:@"input"];
        [respdict setObject:@"input file" forKey:@"status"];
        [response respondWithString: [_jsonwriter stringWithObject:respdict]];
        [self savePrefs];
    }];
    
    // add a URL watching input
    [http get:@"/blink1/input/url" withBlock:^(RouteRequest *request, RouteResponse *response) {
        NSString* iname = [request param:@"iname"];
        NSString* url   = [request param:@"url"];
        
        NSMutableDictionary* input = [[NSMutableDictionary alloc] init];
        if( iname != nil && url != nil ) { // the minimum requirements for this input type
            [input setObject:iname  forKey:@"iname"];
            [input setObject:@"url" forKey:@"type"];
            [input setObject:url    forKey:@"arg"];
            [inputs setObject:input forKey:iname];  // add new input to inputs list
        }
        
        NSMutableDictionary *respdict = [NSMutableDictionary dictionaryWithDictionary:input];
        [respdict setObject:input forKey:@"input"];
        [respdict setObject:@"input url" forKey:@"status"];
        [response respondWithString: [_jsonwriter stringWithObject:respdict]];
        [self savePrefs];
    }];
    
    // add the ifttt watching input
    [http get:@"/blink1/input/ifttt" withBlock:^(RouteRequest *request, RouteResponse *response) {
        NSString* enable = [request param:@"enable"];
        // FIXME: handle enable

        NSMutableDictionary *respdict = [[NSMutableDictionary alloc] init];
        [respdict setObject:enable forKey:@"status"];
        [response respondWithString: [_jsonwriter stringWithObject:respdict]];
        [self savePrefs];
    }];
    
    // add a cpu load watching input
    [http get:@"/blink1/input/cpuload" withBlock:^(RouteRequest *request, RouteResponse *response) {
        NSString* iname = [request param:@"iname"];
        NSString* level = [request param:@"level"];
        NSString* pname = [request param:@"pname"];
        
        //int cpuload = [cpuuse getCPUuse];
        //NSLog(@"cpu use:%d%%",cpuload);
        
        NSMutableDictionary* input = [[NSMutableDictionary alloc] init];
        if( iname != nil && level != nil ) {
            if( pname == nil ) pname = iname;
            [input setObject:iname      forKey:@"iname"];
            [input setObject:@"cpuload" forKey:@"type"];
            [input setObject:level      forKey:@"arg"];
            [input setObject:pname      forKey:@"pname"];
            [inputs setObject:input forKey:iname];
        }

        NSMutableDictionary *respdict = [NSMutableDictionary dictionaryWithDictionary:input];
        //[respdict setObject:[NSNumber numberWithInt:cpuload] forKey:@"cpuload"];
        [respdict setObject:@"cpuload" forKey:@"status"];
        [response respondWithString: [_jsonwriter stringWithObject:respdict]];
        [self savePrefs];
    }];

    // add a network load watching input
    [http get:@"/blink1/input/netload" withBlock:^(RouteRequest *request, RouteResponse *response) {
        NSString* iname = [request param:@"iname"];
        NSString* level = [request param:@"level"];
        NSString* pname = [request param:@"pname"];

        NSMutableDictionary *respdict = [[NSMutableDictionary alloc] init];
        [respdict setObject:iname forKey:@"iname"];
        [respdict setObject:level forKey:@"level"];
        [respdict setObject:pname forKey:@"pname"];
        [respdict setObject:@"netload not implemented yet" forKey:@"status"];
        [response respondWithString: [_jsonwriter stringWithObject:respdict]];
        [self savePrefs];
    }];
}


// ---------------------------------------------------------------------------
// GUI stuff
// ---------------------------------------------------------------------------

//
- (void) awakeFromNib
{
    [self activateStatusMenu];
}

//
// Put status bar icon up on the screen
// Two icon files, one for the "normal" state and one for the "highlight" state.
// These icons should be 18x18 pixels in size, and should be done as PNGs
// so you can get the transparency you need.
// (http://www.sonsothunder.com/devres/revolution/tutorials/StatusMenu.html)
//
- (void) activateStatusMenu
{
    statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];

    //Allocates and loads the images into the application which will be used for our NSStatusItem
    NSBundle *bundle = [NSBundle mainBundle];    
    statusImage = [[NSImage alloc] initWithContentsOfFile:[bundle pathForResource:@"blink1iconA1" ofType:@"png"]];
    //statusHighlightImage = [[NSImage alloc] initWithContentsOfFile:[bundle pathForResource:@"blink1iconA1i" ofType:@"png"]];
    //Sets the images in our NSStatusItem
    [statusItem setImage:statusImage];
    //[statusItem setAlternateImage:statusHighlightImage];
    
    //[statusItem setTitle: NSLocalizedString(@"blink(1)",@"")];
    [statusItem setHighlightMode:YES];
    [statusItem setMenu:statusMenu];  // instead, we'll do it by hand
    
    //[statusItem setAction:@selector(openStatusMenu:)];
    //[statusItem setTarget:self];
}

//FIXME: what's the better way of doing this?
- (void) updateUI
{
    if( [[blink1 serialnums] count] ) {
        NSString* serstr = [[blink1 serialnums] objectAtIndex:0];
        [_blink1serial setTitle: [NSString stringWithFormat:@"serial:%@",serstr]];
        [_blink1status setTitle: @"blink(1) found"];
    }
    else {
        [_blink1serial setTitle: @"serial:-none-"];
        [_blink1status setTitle: @"blink(1) not found"];
    }

}

// GUI action:
- (IBAction) openStatusMenu: (id) sender
{
    [blink1 enumerate];
    [self updateUI];
    
    //[NSTimer scheduledTimerWithTimeInterval:10 target:self selector:@selector(showMenu) userInfo:nil repeats:NO];
    //[NSApp activateIgnoringOtherApps:YES];
    [statusItem popUpStatusItemMenu:statusMenu];
}

// GUI action: open up main config page
- (IBAction) openConfig: (id) sender
{
    DLog(@"Config!");
    [blink1 enumerate];
    [self updateUI];
    
    // Load the HTML content.
    //[[[_webView mainFrame] frameView] setAllowsScrolling:NO];
    [[_webView mainFrame] loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:confURL]]];
    [_window display];
    [_window setIsVisible:YES];
    [NSApp activateIgnoringOtherApps:YES];
}

// GUI action: open up 'play' page (currently used for testing alternate interface)
- (IBAction) playIt: (id) sender
{
    DLog(@"Play!");

    [[_webView mainFrame] loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:playURL]]];
    [_window display];
    [_window setIsVisible:YES];
    [NSApp activateIgnoringOtherApps:YES];
}

// GUI action: turn off blink1
- (IBAction) allOff: (id) sender
{
    DLog(@"allOff");
    [self stopPattern:@"all"];
    [blink1 fadeToRGB:[Blink1 colorFromHexRGB: @"#000000"] atTime:0.1];
}

// GUI action: unused, rescan is done on config open now
- (IBAction) reScan: (id) sender
{
    [blink1 enumerate];
    [self updateUI];
    
    //[NSTimer scheduledTimerWithTimeInterval:10 target:self selector:@selector(showMenu) userInfo:nil repeats:NO];
    //[NSApp activateIgnoringOtherApps:YES];
    [statusItem popUpStatusItemMenu:statusMenu];
    
}

// GUI action: quit the app
- (IBAction) quit: (id) sender
{
    DLog(@"Quit!");
    [self savePrefs];
    [NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0.0];
}



@end


/*
 // testing Task
 NSString*	result;
 result = [Task runWithToolPath:@"/usr/bin/grep" arguments:[NSArray arrayWithObject:@"france"] inputString:@"bonjour!\nvive la france!\nau revoir!" timeOut:0.0];
 NSLog(@"result: %@", result);
 
 result = [Task runWithToolPath:@"/bin/sleep" arguments:[NSArray arrayWithObject:@"2"] inputString:nil timeOut:1.0];
 NSLog(@"result: %@", result);
 */


/*
 NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
 NSString *myString = [prefs stringForKey:@"keyToLookupString"];      // getting an NSString
 if( myString == nil ) {
 // saving an NSString
 [prefs setObject:@"TextToSave" forKey:@"keyToLookupString"];
 }
 */
/*
 NSString* iname = @"myTodInput";
 NSMutableDictionary* input = [[NSMutableDictionary alloc] init];
 [input setObject:iname forKey:@"iname"];
 [input setObject:@"todftt" forKey:@"type"];
 [input setObject:@"blargh" forKey:@"arg"];
 [inputs setObject:input forKey:iname];
 */




/*
 [http get:@"/hello/:name" withBlock:^(RouteRequest *request, RouteResponse *response) {
 [response respondWithString:[NSString stringWithFormat:@"Hello %@!", [request param:@"name"]]];
 }];
 
 [http get:@"{^/page/(\\d+)}" withBlock:^(RouteRequest *request, RouteResponse *response) {
 [response respondWithString:[NSString stringWithFormat:@"You requested page %@",
 [[request param:@"captures"] objectAtIndex:0]]];
 }];
 
 [http post:@"/widgets" withBlock:^(RouteRequest *request, RouteResponse *response) {
 // Create a new widget, [request body] contains the POST body data.
 // For this example we're just going to echo it back.
 [response respondWithData:[request body]];
 }];
 
 // Routes can also be handled through selectors
 [http handleMethod:@"GET" withPath:@"/selector" target:self     selector:@selector(handleSelectorRequest:withResponse:)];
 */


/*
 NSString *jsonString = @"{\"tod\":1, \"bar\":2, \"garb\":\"gobble\", \"arrr\":[ 3,6,89] }";
 
 id object = [_jsonparser objectWithString:jsonString];
 //if (object) {
 NSLog(@"val:%@",[_jsonwriter stringWithObject:object]);
 //} else {
 NSLog(@"error:%@",[NSString stringWithFormat:@"An error occurred: %@", _jsonparser.error]);
 //}
 
 NSMutableDictionary *dictionary = [[NSMutableDictionary alloc] init];
 [dictionary setObject:@"tod kurt" forKey:@"todbot"];
 [dictionary setObject:@"carlyn maw" forKey:@"carlynorama"];
 NSLog(@"dict:%@",[_jsonwriter stringWithObject:dictionary]);
 */
