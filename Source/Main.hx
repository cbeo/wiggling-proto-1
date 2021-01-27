package;

import openfl.display.Sprite;
import openfl.events.MouseEvent;
import openfl.events.KeyboardEvent;
import openfl.events.Event;
import openfl.events.TimerEvent;
import openfl.ui.Keyboard;
import openfl.utils.Timer;
import haxe.ds.Option;

using Lambda;

typedef Pt= {x:Float, y:Float};

typedef Rect = Pt & {width:Float, height:Float};

enum Line {
  Vertical(xVal:Float);
  Horizontal(yVal:Float);
  Sloped(slop:Float,yIntercept:Float);
}

typedef Circle = Pt & {radius:Float, ?vx:Float, ?vy:Float, ?color:Int};
typedef Neighbor = {circle:Circle, distance:Float};


class Main extends Sprite
{

  var drawing = false;
  var timestamp:Float;
  //  var animating = false;

  var circleTrials = 10000;

  var sampleRate:Float = 0.01;
  var sampleGap:Float = 5.0;

  var path:Array<Pt>;

  var radiiSizes = 10;
  var radiusGradient = 3.0;
  var circles:Array<Circle> = [];
  var neighborRadius : Float;
  var driftTolerance = 0.5; // 8%

  var dontDrawLargerThan = 200;

  //  var minSubgraphSize = 1;
  //var maxSubgraphSize = 3;
  var topology:Map<Circle,Array<Neighbor>> = new Map();
  var nearestCircle:Map<Pt,{circle:Circle, dx:Float,dy:Float}> = new Map();

  var framePause = 1.0 / 4;
  var animTimer : Timer;
  
  public function new()
  {
    super();
    neighborRadius = radiiSizes * radiusGradient * 1.5;

    stage.addEventListener( MouseEvent.MOUSE_DOWN, onMouseDown);
    stage.addEventListener( MouseEvent.MOUSE_UP, onMouseUp);
    stage.addEventListener( MouseEvent.MOUSE_MOVE, onMouseMove);
    //stage.addEventListener( Event.ENTER_FRAME, perFrame);
    animTimer = new Timer( framePause );
    animTimer.addEventListener( TimerEvent.TIMER, perFrame);
  }

  function addNearestCircles()
  {
    nearestCircle = new Map();
    for (pt in path)
      {
        var circs = circles.copy();
        circs.sort( (a,b) -> Std.int(ptDist(a,pt) - ptDist(b,pt)));
        nearestCircle[pt] = {circle: circs[0], dx: pt.x - circs[0].x, dy: pt.y - circs[0].y};
      }
  }

  function addCircles()
  {
    circles = [];
    if (path.length > 2 && !drawing)
      {
        var bbox = pathBoundingBox();
        var rad = radiusGradient * radiiSizes;
        while (rad > 0) {
          for (i in 0...circleTrials) {
            var circ = randomCircle(bbox, rad);
            if ( validCircle(circ)) circles.push(circ);
          }
          rad -= radiusGradient;
        }
      }
  }


  function isNeighbor(c1: Circle, c2:Circle) :Bool
  {
    var nbrs = topology[c1];
    return nbrs != null && nbrs.exists( n -> n.circle == c2);
  }

  function newTopology ()
  {
    var top:Map<Circle,Array<Neighbor>> = new Map();
    for (c in circles)
      top[c] = [];
    return top;
  }
  
  function addTopology ()
  {
    topology = newTopology();

    var isNeighbor = (a:Circle, b:Circle) ->
      topology[a].exists( node -> node.circle == b );
    
    var areNeighbors = (a:Circle,b:Circle) ->
      isNeighbor(a,b) || isNeighbor(b, a);
    
    // var needsNeighbor = (a:Circle) ->
    //   topology[a].length < minSubgraphSize;

    var validNeighbor = (a:Circle,b:Circle) -> 
      return a != b &&
      !areNeighbors( a, b ) &&
      ptDist(a,b) < neighborRadius &&
      !lineIntersectsPath(a, b);

    var connect = (a:Circle , b:Circle) -> {
      //component[b] = component[a];
      var dist = ptDist(a,b);
      topology[b].push({circle:a, distance: dist});
      topology[a].push({circle:b, distance: dist});
    }
    
    for (c1 in circles)
      for (c2 in circles)
        if ( validNeighbor( c1, c2 ) )
          connect(c1,c2);
  }

  function lineIntersectsPath(a:Pt,b:Pt):Bool
  {
    for (i in 0...path.length - 1)
      if ( linesIntersect(a,b,path[i],path[i+1])) return true;

    return linesIntersect(a,b,path[path.length - 1],path[0]);
  }

  function lineIntersectsPathAt(a:Pt,b:Pt):Array<Pt>
  {
    var intersections = [];

    for (i in 0...path.length - 1)
      switch (linesIntersectAt(a,b,path[i],path[i+1]))
        {
        case Some(pt): intersections.push( pt );
        case None: {}
        }

    switch ( linesIntersectAt(a,b,path[path.length - 1],path[0]))
      {
      case Some(pt):intersections.push(pt);
      case None:{}
      }

    return intersections;
  }

  function validCircle(circ:Circle):Bool
  {
    return circleInsideClosedPath(circ) && !circleIntersectsCircles(circ);
  }
  
  function circleInsideClosedPath (c:Circle):Bool
  {
    return pointInsideClosedPath(c) && !circleIntersectsPath( c );
  }
  
  function pointInsideClosedPath(pt:Pt):Bool
  {
    var intersections = 0;
    var leftPt : Pt = { x: 0, y: pt.y};

    for (i in 0...path.length-1)
      if (linesIntersect( leftPt, pt, path[i], path[i + 1] ))
        intersections += 1;

    if (linesIntersect( leftPt, pt, path[path.length - 1], path[0]))
      intersections += 1;

    return intersections % 2 == 1;
  }

  function circleIntersectsCircles( circ:Circle):Bool
  {
    for (c in circles) if (circlesIntersect(c, circ)) return true;
    return false;
  }
  
  function circleIntersectsLine(circ:Circle,line:Line):Bool
  {
    switch (line)
      {
      case Vertical(xVal):
        return Math.abs(circ.x - xVal) <= circ.radius;

      case Horizontal(yVal):
        return Math.abs(circ.y - yVal) <= circ.radius;

      case Sloped(m, yInt):
        var a = (m*m + 1);
        var k = yInt - circ.y;
        var b = 2 * (m*k - circ.x);
        var c = (k * k + circ.x * circ.x - circ.radius * circ.radius);

        var discriminant = b * b - 4 * a * c;
        return discriminant >= 0;
      }
  }

  function isBetween(a:Float, b:Float, c:Float):Bool
  {
    if (a < c)
      return a <= b && b <= c;

    return c <= b && b <= a;
  }

  function circleIntersectsPath( circ:Circle ):Bool
  {

    for (i in 0...path.length - 1)
      {
        if (circleContainsPt( circ, path[i] ))
          return true;
        
        if (circleContainsPt( circ, path[i+1]))
          return true;
        
        if ( circleIntersectsLine( circ, lineOfSegment( path[i], path[i + 1])) &&
             (isBetween( path[i].x, circ.x, path[i+1].x) ||
              isBetween( path[i].y, circ.y, path[i+1].y)))
          return true;
      }
    
    return false;
  }

  static function circleContainsPt( circle:Circle, pt:Pt):Bool
  {
    return circle.radius >= ptDist(circle, pt);
  }

  static function randomCircle(bbox:Rect, rad:Float):Circle
  {
    var cx = (Math.random() * bbox.width) + bbox.x;
    var cy = (Math.random() * bbox.height) + bbox.y;
    var vx = Math.random() * (if (Math.random() > 0.5) 1 else -1);
    var vy = Math.random() * (if (Math.random() > 0.5) 1 else -1);
    var color = Std.int( Math.random() * 0xFFFFFF);
    return {radius:rad, x: cx, y:cy, vx:vx, vy:vy, color:color};
  }
  
  static function circlesIntersect(c1:Circle,c2:Circle):Bool
  {
    return ptDist(c1, c2) <= c1.radius + c2.radius;
  }

  static function circleContains(c1:Circle,c2:Circle):Bool
  {
    return c2.radius <= c1.radius && ptDist(c1,c2) <= c1.radius;
  }

  function findSelfIntersectionIndex (p:Pt ) : Option<Int>
  {
    if ( path.length > 0) {
      var last = path.length - 1;

      for (i in 1 ... last) 
        if (linesIntersect( path[i-1], path[i], path[last], p)) 
          return Some(i);
    }
    return None;      
  }

  function findSelfIntersectionPt (p:Pt ) : Option<Pt>
  {
    if ( path.length > 0) {
      var last = path.length - 1;

      for (i in 1 ... last) 
        if (linesIntersect( path[i-1], path[i], path[last], p)) 
          return linesIntersectAt( path[i-1], path[i], path[last], p );
    }
    return None;      
  }
  
  function selfIntersectionCheck( p:Pt ) : Bool
  {
    return switch (findSelfIntersectionIndex( p ))
      {
      case  Some(_): true;
      case None: false;
      };
  }
  
  function onMouseDown (e)
  {
    drawing = true;
    //animating = false;
    if (animTimer.running) animTimer.stop();
    timestamp = haxe.Timer.stamp();
    path = [ {x:e.localX, y:e.localY} ];

    graphics.clear();
    graphics.lineStyle(3,0);
    graphics.moveTo( e.localX, e.localY );
  }

  function onMouseUp (e)
  {
    drawing = false;
  }

  function drawCircle(c:Circle)
  {
    if ( c.radius <= dontDrawLargerThan)
      {
        graphics.beginFill( c.color , 0.7);
        graphics.drawCircle( c.x, c.y, c.radius );
      }
  }

  function drawCircles()
  {
    for (c in circles) drawCircle(c);
  }

  function drawTopology()
  {
    //graphics.lineStyle(1,0);
    graphics.beginFill(0);
    for (pt in topology.keys()) {
      graphics.moveTo( pt.x, pt.y );      
      for (nbr in topology[pt]) {
        graphics.lineTo( nbr.circle.x, nbr.circle.y );
      }
      graphics.lineTo( pt.x , pt.y);
    }
  }

  function render()
  {
    graphics.clear();
    adjustPathAndDraw();
    drawCircles();
    //drawTopology();

  }

  
  function pathBoundingBox () : Rect
  {
    if (path.length == 0)
      return {x:0,y:0,width:0,height:0};

    var leftMost = path[0].x;
    var rightMost = leftMost;
    var topMost = path[0].y;
    var bottomMost = topMost;

    for (pt in path)
      {
        leftMost = Math.min( leftMost, pt.x);
        rightMost = Math.max( rightMost, pt.x);
        topMost = Math.min( topMost, pt.y);
        bottomMost = Math.max( bottomMost, pt.y);
      }

    return {x:leftMost, y: topMost, width: rightMost - leftMost, height: bottomMost - topMost};
  }

  function pathEdgeDistances()
  {
    if (path.length > 1) {

      var max = ptDist(path[0],path[1]);
      var min = max;
      
      for (i in 0...path.length-2)
        {
          var dist = ptDist( path[i], path[i+1]);
          max = Math.max(max, dist);
          min = Math.min(min,dist);
        }
      return {max:max,min:min};
    }
    return null;
  }

  function pathIsCounterClockwise () : Bool
  {
    return path.length > 2 &&  isCounterClockwiseOrder(path[0],path[1],path[2]);
  }
  
  function onMouseMove (e)
  {
    var stamp = haxe.Timer.stamp();
    var pt = {x:e.localX, y:e.localY};

    if (drawing && (stamp - timestamp > sampleRate) && ptDist(pt, path[path.length-1]) >= sampleGap) {
      switch (findSelfIntersectionIndex( pt ))
        {
        case Some(i):
          var firstAndLastOption = findSelfIntersectionPt( pt );
          drawing = false;
          path = path.slice(i);

          var firstAndLast = switch(firstAndLastOption)
            {case Some(pt):pt; default:path[0];};

          path[0] = firstAndLast;

          if (pathIsCounterClockwise())
            path.reverse();

          addCircles();
          addTopology();
          addNearestCircles();
          //render();
          
          animTimer.start();

          return; // exiting early.. a little ugly.
          
        case None: {}
        }      

      timestamp = stamp;
      path.push( pt );
      graphics.lineTo( e.localX, e.localY );
    }
    
  }

  function adjustPathAndDraw ()
  {
    var first = path[0];
    var nearest = nearestCircle[first];
    first.x = nearest.circle.x + nearest.dx;
    first.y = nearest.circle.y + nearest.dy;

    graphics.lineStyle(radiusGradient * 2, 0);
    graphics.beginFill(0xfaeeee);
    graphics.moveTo(first.x, first.y);

    for (pt in path.slice(1))
      {
        nearest = nearestCircle[pt];
        pt.x = nearest.circle.x + nearest.dx; // not really needed
        pt.y = nearest.circle.y + nearest.dy; // not really needed
        graphics.lineTo( pt.x, pt.y);
        //graphics.curveTo(pt.x, pt.y, nearest.circle.x, nearest.circle.y);
      }

    graphics.lineTo(first.x, first.y);
  }



  function moveCircles ()
  {
    var stamp  = haxe.Timer.stamp();
    var cosStamp = Math.cos( stamp);
    var sinStamp = Math.sin(stamp);
    for (c in circles)
      {
        var vx = 0.0;
        var vy = 0.0;
        for (nbr in topology[c])
          {
            var dist = ptDist(c, nbr.circle);
            var dx = nbr.circle.x - c.x;
            var dy = nbr.circle.y - c.y;

            var radRatio = nbr.circle.radius / c.radius;

            //end of tether case
            if ( Math.abs(dist - nbr.distance) / nbr.distance > driftTolerance)
                 // || circlesIntersect(c, nbr.circle))
              {
                vx += nbr.circle.vx / dx * radRatio;
                vy += nbr.circle.vy / dy * radRatio;
              }
            else 
              {
                vx += c.vx; // will average out later
                vy += c.vy;
              }
            // else if (nbr.circle.radius > c.radius) // normal caase
            //   {
            //     vx += (dx / (dist));// * Math.sqrt(nbr.circle.radius / c.radius);
            //     vy += (dy / (dist));// * Math.sqrt(nbr.circle.radius / c.radius);
            //   }
          }


        c.vx = (c.vx + vx) / (topology[c].length + 1);
        c.vy = (c.vy + vy) / (topology[c].length + 1);

        if (c.x >= stage.stageWidth || c.x <= 0)
          c.vx *= -1;

        if (c.y >= stage.stageHeight || c.y <= 0)
          c.vy *= -1;


        c.x += c.vx ;// + cosStamp * c.x / stage.stageWidth;
        c.y += c.vy ; // + sinStamp * c.y / stage.stageHeight;

        c.x = Math.max( 0, Math.min( stage.stageWidth,  c.x ));
        c.y = Math.max( 0, Math.min( stage.stageHeight, c.y ));
      }
  }


  function perFrame (e)
  {
    moveCircles();
    render();
  }

  static function ptDist(p1:Pt,p2:Pt) : Float
  {
    if (p1 == null || p2 == null) return 0;
    var dx = p2.x - p1.x;
    var dy = p2.y - p1.y;
    return Math.sqrt( dx*dx + dy*dy);
  }


  static function lineOfSegment (a:Pt,b:Pt):Line
  {
    if (a.x == b.x)
      return Vertical(a.y);

    if (a.y == b.y)
      return Horizontal(a.x);

    var slope = (b.y - a.y) / (b.x - a.x);
    var yIntercept = a.y - slope * a.x;
    return Sloped(slope,yIntercept);
  }

  static function isCounterClockwiseOrder(a:Pt,b:Pt,c:Pt) {
    return (b.x - a.x) * (c.y - a.y) > (b.y - a.y) * (c.x - a.x);
  }

  static function linesIntersect (a:Pt,b:Pt,c:Pt,d:Pt) : Bool {
    return (isCounterClockwiseOrder( a, c, d) != isCounterClockwiseOrder(b, c, d)) &&
      (isCounterClockwiseOrder( a ,b, c) != isCounterClockwiseOrder(a, b, d));
  }

  static function linesIntersectAt (a:Pt,b:Pt,c:Pt,d:Pt) : Option<Pt>
  {
    var line1 = lineOfSegment(a,b);
    var line2 = lineOfSegment(c,d);

    switch ([line1, line2])
      {
      case [Sloped(m1,b1), Sloped(m2,b2)]:
        var x = (b2 - b1) / (m1 - m2);
        var y = m1 * x + b1;
        return Some({x:x,y:y});

      case [Sloped(m,b), Vertical(x)] | [Vertical(x), Sloped(m,b)]:
        var y = m * x + b;
        return Some({x:x,y:y});

      case [Sloped(m,b), Horizontal(y)] | [Horizontal(y), Sloped(m,b)]:
        var x = (y - b) / m;
        return Some({x:x,y:y});

      case [Horizontal(y),Vertical(x)] | [Vertical(y), Horizontal(x)]:
        return Some({x:x,y:y});

      default:
        return None;
      }
  }

}

