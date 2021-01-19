package;

import openfl.display.Sprite;
import openfl.events.MouseEvent;
import openfl.events.KeyboardEvent;
import openfl.ui.Keyboard;
import haxe.Timer;
import haxe.ds.Option;

typedef Pt= {x:Float, y:Float};

typedef Rect = Pt & {width:Float, height:Float};

enum Line {
  Vertical(xVal:Float);
  Horizontal(yVal:Float);
  Sloped(slop:Float,yIntercept:Float);
}

typedef Circle = Pt & {radius:Float};

class Main extends Sprite
{

  var drawing = false;
  var timestamp:Float;

  var sampleRate:Float = 0.01;
  var sampleGap:Float = 15.0;

  var path:Array<Pt>;

  var radiiSizes = 4;
  var radiusGradient = 10.0;
  var circles:Array<Circle> = [];

  var subgraphSize = 3;
  var topology:Map<Pt,Array<Circle>> = new Map();
  
  public function new()
  {
    super();
    stage.addEventListener( MouseEvent.MOUSE_DOWN, onMouseDown);
    stage.addEventListener( MouseEvent.MOUSE_UP, onMouseUp);
    stage.addEventListener( MouseEvent.MOUSE_MOVE, onMouseMove);
  }

  function addCircles()
  {
    circles = [];
    if (path.length > 2 && !drawing)
      {
        var bbox = pathBoundingBox();
        var rad = radiusGradient * radiiSizes;
        while (rad > 0) {
          for (i in 0...500) {
            var circ = randomCircle(bbox, rad);
            if ( validCircle(circ)) circles.push(circ);
          }
          rad -= radiusGradient;
        }
      }
  }

  function addTopology()
  {
    topology = new Map();
    var allShit = (circles:Array<Pt>).concat(path);


    for (c1 in allShit) {
      var nbrs = [];

      for (c2 in circles)
        if (c2 != c1 && !(lineIntersectsPath(c1, c2))) {

          if (nbrs.length < subgraphSize) {
            nbrs.push( c2 );
          } else {
            var dist = ptDist( c1, c2 );
            var traversing = true;
            var i = 0;
            while (traversing && i < subgraphSize) {
              if (dist < ptDist(c1, nbrs[i])) {
                nbrs[i] = c2;
                traversing = false;
              }
              i += 1;
            }
          }
        }
      topology[c1] = nbrs;
    }
  }

  


  // circles are points
  function nearestValidNeighbors(center:Pt, n:Int):Array<Pt>
  {
    var nearest = [];

    for (pt in circles)
      if (pt != center && (!lineIntersectsPath(center,pt) || path.contains( center )))
        if (nearest.length < n) {
          nearest.push(pt);
        } else {
          var d = ptDist(pt, center);
          nearest = [for (np in nearest) if (d < ptDist(np,center)) pt else np];
        }

    return nearest;
  }

  function lineIntersectsPath(a:Pt,b:Pt):Bool
  {
    for (i in 0...path.length - 1)
      if ( linesIntersect(a,b,path[i],path[i+1])) return true;

    return linesIntersect(a,b,path[path.length - 1],path[0]);
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
    return {radius:rad, x: cx, y:cy};
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
    timestamp = Timer.stamp();
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
    graphics.drawCircle( c.x, c.y, c.radius );
  }

  function drawCircles()
  {
    graphics.lineStyle(1,0xff0000);
    for (c in circles) drawCircle(c);
    for (pt in path) drawCircle({x:pt.x, y:pt.y, radius:2});
  }

  function drawTopology()
  {
    graphics.lineStyle(1,0x0000ff);
    for (pt in topology.keys())
      for (nbr in topology[pt]) {
        graphics.moveTo( pt.x, pt.y );
        graphics.lineTo( nbr.x, nbr.y );
      }
  }

  function drawNearestNeighbors(n:Int)
  {
    graphics.lineStyle(2,0x0000ff);
    for (c in circles)
      for (nbr in nearestValidNeighbors(c, n)) {
        graphics.moveTo(c.x,c.y);
        graphics.lineTo(nbr.x,nbr.y);
      }
    // for (c in path)
    //   for (nbr in nearestValidNeighbors(c, n)) {
    //     graphics.moveTo(c.x,c.y);
    //     graphics.lineTo(nbr.x,nbr.y);
    //   }
  }

  function render()
  {
    graphics.clear();

    graphics.moveTo( path[0].x,  path[0].y );

    for (i in 1...path.length) {
      graphics.lineStyle(2, 0);
      graphics.lineTo( path[i].x, path[i].y );
    }

    graphics.lineStyle(2, 0);
    graphics.lineTo(path[0].x, path[0].y);

    
    
    // var bbox = pathBoundingBox();
    // graphics.lineStyle(1,0x00ff00);
    // graphics.drawRect(bbox.x,bbox.y,bbox.width,bbox.height);

    drawCircles();
    drawTopology();
    //drawNearestNeighbors(4);
    
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

  function onMouseMove (e)
  {
    var stamp = Timer.stamp();
    var pt = {x:e.localX, y:e.localY};

    if (drawing && (stamp - timestamp > sampleRate) && ptDist(pt, path[path.length-1]) >= sampleGap) {
      switch (findSelfIntersectionIndex( pt ))
        {
        case Some(i):
          var firstAndLastOption = findSelfIntersectionPt( pt );
          drawing = false;
          path = path.slice(i);

          trace(firstAndLastOption);
          var firstAndLast = switch(firstAndLastOption)
            {case Some(pt):pt; default:path[0];};

          trace( firstAndLast );
          
          path[0] = firstAndLast;

          addCircles();
          addTopology();
          render();
          
          trace("path edge differences: ");
          trace( pathEdgeDistances()) ;

          trace('path.length = ${path.length}');
          trace('circles.length = ${circles.length}');

          var sizes = [];

          for (c in circles)
            if (!sizes.contains( c.radius ))
              sizes.push( c.radius );

          trace('circle sizes = $sizes');

          trace('');
          return; // exiting early.. a little ugly.
          
        case None: {}
        }      

      timestamp = stamp;
      path.push( pt );
      graphics.lineTo( e.localX, e.localY );
    }
    
  }

  static function ptDist(p1:Pt,p2:Pt)
  {
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

    trace([line1, line2]);
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
