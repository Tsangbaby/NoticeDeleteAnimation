// Real CoreGraphics geometry invariant tests for production renderer placement.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "NLRenderGeometry.h"
#include <stdio.h>
static NSUInteger checks;
static void require(BOOL ok, const char *name) {
    if (!ok) { fprintf(stderr,"GEOMETRY NATIVE FAIL: %s\n",name); exit(1); }
    ++checks;
}
int main(void) {
 @autoreleasepool {
    const CGRect viewport = {{0,0},{390,844}};
    const CGRect cards[] = {{{20,180},{300,90}},{{-183,521},{370,80}},{{10,20},{200,60}},{{30,700},{320,80}}};
    for (NSUInteger i=0;i<sizeof(cards)/sizeof(cards[0]);++i) {
        CGRect frame,local;
        require(NLMakeRenderGeometry(cards[i],viewport,110,&frame,&local),"valid observed card");
        require(CGRectEqualToRect(CGRectOffset(local,frame.origin.x,frame.origin.y),cards[i]),"local card plus viewport origin equals actual overlay card");
        require(CGRectContainsRect(viewport,frame),"particle viewport stays in window");
        require(frame.size.height>=cards[i].size.height,"canvas is not card-sized crop of nonzero origin");
        if(i==0) require(local.origin.y!=cards[i].origin.y || frame.origin.y==0,"no duplicate nonzero y");
    }
    CGRect f,l;CGRect shifted={{-50,100},{390,844}};CGRect card={{-20,200},{300,90}};
    require(NLMakeRenderGeometry(card,shifted,40,&f,&l),"nonzero window bounds origin");
    require(CGRectEqualToRect(CGRectOffset(l,f.origin.x,f.origin.y),card),"shifted viewport local mapping");
    require(!NLMakeRenderGeometry(card,shifted,NAN,&f,&l),"invalid distance");
    require(!NLMakeRenderGeometry(CGRectNull,viewport,20,&f,&l),"null card");
    require(!NLMakeRenderGeometry(CGRectMake(INFINITY,0,1,1),viewport,20,&f,&l),"infinite origin");
    require(!NLMakeRenderGeometry(CGRectMake(0,0,-1,1),viewport,20,&f,&l),"negative card");
    require(!NLMakeRenderGeometry(CGRectMake(2000,2000,10,10),viewport,20,&f,&l),"fully offscreen card");
    require(!NLMakeRenderGeometry(card,viewport,20,NULL,&l),"missing output");
    printf("GEOMETRY NATIVE PASS: %lu checks; actual production CoreGraphics helper, no Metal draw claim\n",(unsigned long)checks);
 }
 return 0;
}
