import AppKit
import Foundation

// Usage: swift scripts/generate-icon.swift <repo root>
// Draws the app icon (ceramic orb wearing AirPods) and the monochrome menu bar template.
let root=URL(fileURLWithPath:CommandLine.arguments[1])
let catalog=root.appendingPathComponent("HeadControl/Resources/Assets.xcassets")
let output=catalog.appendingPathComponent("AppIcon.appiconset")
try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)

func rgb(_ r:CGFloat,_ g:CGFloat,_ b:CGFloat)->NSColor { NSColor(srgbRed:r,green:g,blue:b,alpha:1) }
func oval(_ cx:CGFloat,_ cy:CGFloat,_ w:CGFloat,_ h:CGFloat)->NSBezierPath { NSBezierPath(ovalIn:NSRect(x:cx-w/2,y:cy-h/2,width:w,height:h)) }
func render(_ pixel:Int,_ draw:(CGFloat)->Void) -> NSBitmapImageRep {
    guard let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixel,pixelsHigh:pixel,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let context=NSGraphicsContext(bitmapImageRep:bitmap) else { fatalError("icon context") }
    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context
    draw(CGFloat(pixel))
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

/// Front view of the ceramic orb wearing AirPods, in unit coordinates (0…1) scaled by `s`, origin bottom-left.
func orb(_ s:CGFloat) {
    let c=NSPoint(x:0.5*s,y:0.5*s),r=0.34*s
    let ball=oval(c.x,c.y,2*r,2*r)
    // Soft shadow under the orb.
    NSColor(white:0,alpha:0.18).setFill();oval(c.x,0.13*s,1.3*r,0.16*r).fill()
    // Ceramic shading: light from upper left.
    NSGradient(colors:[rgb(1,1,1),rgb(0.90,0.91,0.93),rgb(0.70,0.72,0.76)],atLocations:[0,0.55,1],colorSpace:.sRGB)!
        .draw(in:ball,relativeCenterPosition:NSPoint(x:-0.35,y:0.4))
    // Equator and meridian, clipped to the ball.
    NSGraphicsContext.saveGraphicsState();ball.addClip()
    rgb(0.55,0.57,0.62).setStroke()
    let equator=oval(c.x,c.y-0.04*s,2*r,0.42*r);equator.lineWidth=max(1,0.012*s);equator.stroke()
    let meridian=NSBezierPath();meridian.move(to:NSPoint(x:c.x,y:c.y+r));meridian.line(to:NSPoint(x:c.x,y:c.y-r))
    meridian.lineWidth=max(1,0.012*s);meridian.stroke()
    NSGraphicsContext.restoreGraphicsState()
    // AirPods Pro on both sides: bud plus a short stem, with a green status dot.
    for side:CGFloat in [-1,1] {
        let x=c.x+side*(r+0.015*s)
        NSColor(white:0,alpha:0.12).setFill();oval(x+0.006*s,c.y-0.012*s,0.13*s,0.15*s).fill()
        NSColor.white.setFill();oval(x,c.y,0.12*s,0.14*s).fill()
        NSBezierPath(roundedRect:NSRect(x:x-0.022*s+side*0.012*s,y:c.y-0.19*s,width:0.044*s,height:0.15*s),xRadius:0.022*s,yRadius:0.022*s).fill()
        rgb(0.20,0.78,0.35).setFill();oval(x+side*0.03*s,c.y+0.01*s,0.032*s,0.032*s).fill()
    }
}

var images:[[String:String]]=[]
for point in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixel=point*scale
        let bitmap=render(pixel) { side in
            let rect=NSRect(x:side*0.06,y:side*0.06,width:side*0.88,height:side*0.88)
            let bg=NSGradient(starting:rgb(0.55,0.80,0.98),ending:rgb(0.22,0.52,0.90))!
            bg.draw(in:NSBezierPath(roundedRect:rect,xRadius:side*0.195,yRadius:side*0.195),angle:-90)
            NSGraphicsContext.current?.cgContext.translateBy(x:side*0.06,y:side*0.06)
            orb(side*0.88)
        }
        let filename="icon-\(point)@\(scale)x.png"
        try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(filename))
        images.append(["idiom":"mac","size":"\(point)x\(point)","scale":"\(scale)x","filename":filename])
    }
}
let contents:[String:Any] = ["images":images,"info":["author":"xcode","version":1]]
try JSONSerialization.data(withJSONObject:contents,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("Contents.json"))
try Data("{\"info\":{\"author\":\"xcode\",\"version\":1}}".utf8).write(to:catalog.appendingPathComponent("Contents.json"))

// Menu bar template: orb with equator and two AirPods; the system tints it for light/dark menu bars.
let menu=catalog.appendingPathComponent("MenuHead.imageset")
try? FileManager.default.removeItem(at:catalog.appendingPathComponent("MenuOwl.imageset"))
try FileManager.default.createDirectory(at:menu,withIntermediateDirectories:true)
var menuImages:[[String:String]]=[]
for scale in [1,2] {
    let bitmap=render(18*scale) { s in
        NSColor.black.setFill();NSColor.black.setStroke()
        let ring=oval(0.5*s,0.52*s,0.62*s,0.62*s);ring.lineWidth=0.09*s;ring.stroke()
        let equator=NSBezierPath();equator.move(to:NSPoint(x:0.22*s,y:0.50*s))
        equator.curve(to:NSPoint(x:0.78*s,y:0.50*s),controlPoint1:NSPoint(x:0.36*s,y:0.40*s),controlPoint2:NSPoint(x:0.64*s,y:0.40*s))
        equator.lineWidth=0.07*s;equator.stroke()
        for side:CGFloat in [-1,1] {
            let x=0.5+side*0.37
            oval(x*s,0.52*s,0.17*s,0.20*s).fill()
            NSBezierPath(roundedRect:NSRect(x:(x-0.04)*s,y:0.18*s,width:0.08*s,height:0.30*s),xRadius:0.04*s,yRadius:0.04*s).fill()
        }
    }
    let filename="menu-head@\(scale)x.png"
    try bitmap.representation(using:.png,properties:[:])!.write(to:menu.appendingPathComponent(filename))
    menuImages.append(["idiom":"universal","scale":"\(scale)x","filename":filename])
}
let menuContents:[String:Any] = ["images":menuImages,"info":["author":"xcode","version":1],"properties":["template-rendering-intent":"template"]]
try JSONSerialization.data(withJSONObject:menuContents,options:[.prettyPrinted,.sortedKeys]).write(to:menu.appendingPathComponent("Contents.json"))
print("Icons written to \(catalog.path)")
