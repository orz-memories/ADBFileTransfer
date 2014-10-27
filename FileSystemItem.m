/*
 File: FileSystemItem.m
 Abstract:  The data source backend for displaying the file system.
 This object can be improved a great deal; it never frees nodes that are expanded; it also is not too lazy when it comes to computing the children (when the number of children at a level are asked for, it computes the children array).
 Version: 1.2
 
 Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple
 Inc. ("Apple") in consideration of your agreement to the following
 terms, and your use, installation, modification or redistribution of
 this Apple software constitutes acceptance of these terms.  If you do
 not agree with these terms, please do not use, install, modify or
 redistribute this Apple software.
 
 In consideration of your agreement to abide by the following terms, and
 subject to these terms, Apple grants you a personal, non-exclusive
 license, under Apple's copyrights in this original Apple software (the
 "Apple Software"), to use, reproduce, modify and redistribute the Apple
 Software, with or without modifications, in source and/or binary forms;
 provided that if you redistribute the Apple Software in its entirety and
 without modifications, you must retain this notice and the following
 text and disclaimers in all such redistributions of the Apple Software.
 Neither the name, trademarks, service marks or logos of Apple Inc. may
 be used to endorse or promote products derived from the Apple Software
 without specific prior written permission from Apple.  Except as
 expressly stated in this notice, no other rights or licenses, express or
 implied, are granted by Apple herein, including but not limited to any
 patent rights that may be infringed by your derivative works or by other
 works in which the Apple Software may be incorporated.
 
 The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
 MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
 THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
 FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
 OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.
 
 IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
 MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
 AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
 STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.
 
 Copyright (C) 2012 Apple Inc. All Rights Reserved.
 
 */


#import "FileSystemItem.h"


@implementation FileSystemItem

static FileSystemItem *rootItem = nil;

#define IsALeafNode ((id)-1)

- (id)initWithPath:(NSString *)path parent:(FileSystemItem *)obj isDir:(BOOL)dir attributes:(NSString *) attr {
    if (self = [super init]) {
        relativePath = [[path lastPathComponent] copy];
        parent = obj;
        isDir = dir;
        attributes = attr;
    }
    return self;
}

+ (FileSystemItem *)rootItem {
    if (rootItem == nil) rootItem = [[FileSystemItem alloc] initWithPath:@"/" parent:nil isDir: YES attributes: @"dr-xr-xr-x"];
    return rootItem;
}

- (void)dealloc {
    if (children != IsALeafNode) [children release];
    [relativePath release];
    [super dealloc];
}

// Creates and returns the array of children
// Loads children incrementally
//
- (NSArray *)children {
    if (children == NULL) {
        
        BOOL isdir = [self isDir];
        if (isdir) {
            
            NSString *fullPath = [self fullPath];
            NSTask *task;
            task = [[NSTask alloc] init];
            [task setLaunchPath: @"/Users/orzfly/Library/bin/adb"];
            
            NSArray *arguments;
            arguments = [NSArray arrayWithObjects: @"shell", [NSString stringWithFormat:@"ls -l '%@/'", [fullPath stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]], nil];
            [task setArguments: arguments];
            
            NSMutableDictionary* environment = [[NSMutableDictionary alloc] init];
            [environment setValue:@"en_US.utf-8" forKey:@"LANG"];
            [task setEnvironment: environment];
            
            NSPipe *pipe;
            pipe = [NSPipe pipe];
            [task setStandardOutput: pipe];
            
            NSFileHandle *file;
            file = [pipe fileHandleForReading];
            
            [task launch];
            
            NSData *data;
            data = [file readDataToEndOfFile];
            
            NSString *string;
            string = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
            NSLog (@"ping returned:\n%@", string);
            
            NSArray *array = [string componentsSeparatedByString:@"\n"];
            if (!array) {   // This is unexpected
                children = [[NSMutableArray alloc] init];
            } else {
                NSInteger cnt, numChildren = [array count];
                children = [[NSMutableArray alloc] initWithCapacity:numChildren];
                for (cnt = 0; cnt < numChildren; cnt++) {
                    NSMutableArray* result = [[NSMutableArray alloc] init];
                    
                    NSString* line = [array objectAtIndex:cnt];
                    NSError *error = NULL;
                    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^([^ ]+) +([^ ]+) +([^ ]+) +([0-9]+ +)?([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]) (.*?)(?: -> (.*))?$" options:NSRegularExpressionAnchorsMatchLines error:&error];
                    if (regex) {
                        NSTextCheckingResult *match = [regex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
                        
                        for (int groupNumber=1; groupNumber < match.numberOfRanges; groupNumber+=1) {
                            NSRange groupRange = [match rangeAtIndex:groupNumber];
                            if (groupRange.location != NSNotFound)
                                [result addObject: [line substringWithRange:groupRange]];
                            else
                                [result addObject: @""];
                        }
                    } else {
                        // there's a syntax error in the regex
                    }
                    
                    if ([result count] == 7) {
                        BOOL omgDir = NO;
                        if ([[result objectAtIndex:0] characterAtIndex: 0] == 'd')
                            omgDir = YES;
                        
                        FileSystemItem *item = [[FileSystemItem alloc] initWithPath:[result objectAtIndex:5] parent:self isDir: omgDir attributes: [result objectAtIndex:0]];
                        [children addObject:item];
                        [item release];
                    }
                }
            }
            
            [string release];
            
            [task release];
            
        } else {
            children = IsALeafNode;
        }
    }

    return children;
}

- (BOOL) isDir {
    return isDir;
}

- (NSString *)relativePath {
    return relativePath;
}

- (NSString *)attributes {
    return attributes;
}

- (NSString *)fullPath {
    return parent ? [[parent fullPath] stringByAppendingPathComponent:relativePath] : relativePath;
}

- (FileSystemItem *)childAtIndex:(NSInteger)n {
    return [[self children] objectAtIndex:n];
}

- (NSInteger)numberOfChildren {
    if (isDir == NO) return -1;
    id tmp = [self children];
    return (tmp == IsALeafNode) ? (-1) : [tmp count];
}


@end


