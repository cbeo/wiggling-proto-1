package;

import openfl.display.Sprite;
import openfl.events.MouseEvent;
import openfl.events.KeyboardEvent;
import openfl.events.Event;
import openfl.ui.Keyboard;
import haxe.Timer;
import haxe.ds.Option;

using Lambda;

typedef Pt= {x:Float, y:Float};

typedef Rect = Pt & {width:Float, height:Float};

enum Line {
  Vertical(xVal:Float);
  Horizontal(yVal:Float);
  Sloped(slop:Float,yIntercept:Float);
}

typedef Circle = Pt & {radius:Float};
typedef Neighbor = {circle:Circle, distance:Float};


class Main extends Sprite
{

  var drawing = false;
  var timestamp:Float;
  var animating = false;

  var circleTrials = 10000;

  var sampleRate:Float = 0.01;
  var sampleGap:Float = 5.0;

  var path:Array<Pt>;

  var radiiSizes = 6;
  var radiusGradient = 4.0;
  var circles:Array<Circle> = [];

  var subgraphSize = 2;
  var topology:Map<Pt,Array<Neighbor>> = new Map();
  
  public function new()
  {
    super();
    stage.addEventListener( MouseEvent.MOUSE_DOWN, onMouseDown);
    stage.addEventListener( MouseEvent.MOUSE_UP, onMouseUp);
    stage.addEventListener( MouseEvent.MOUSE_MOVE, onMouseMove);
    stage.addEventListener( Event.ENTER_FRAME, perFrame);
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

    // for (pt in path)
    //   circles.push({x:pt.x, y:pt.y, radius:2});
  }


  function isNeighbor(c1: Circle, c2:Circle) :Bool
  {
    var nbrs = topology[c1];
    return nbrs != null && nbrs.exists( n -> n.circle == c2);
  }

  function newTopology ()
  {
    var top:Map<Pt,Array<Neighbor>> = new Map();
    for (c in circles)
      top[c] = [];
    return top;
  }

  // function addTopology()
  // {
  //   topology = newTopology();
  //   for (c1 in circles)
  //     {
  //       var nbrs = topology[c1];
  //       for (c2 in circles)
  //         {
  //           var c2nbrs = topology[ c2 ];
  //           if (c1 != c2 &&
  //               c2nbrs.length < subgraphSize && 
  //               !isNeighbor(c1, c2) &&
  //               !lineIntersectsPath(c1, c2))
  //             {
  //               var dist = ptDist( c1, c2 );
  //               if ( nbrs.length < subgraphSize )
  //                 {
  //                   nbrs.push( { circle: c2, distance: dist } );
  //                   c2nbrs.push( { circle: c1, distance: dist } );
  //                 }
  //               else
  //                 {
  //                   var traversing = true;
  //                   var i = 0;
  //                   while (traversing && i < subgraphSize)
  //                     {
  //                       if (dist < nbrs[i].distance)
  //                         {
  //                           var old = nbrs[i];
  //                           nbrs[i] = {circle:c2, distance:dist};
  //                           c2nbrs.push( {circle: c1, distance: dist} );
  //                           traversing = false;
  //                           topology[old.circle] =
  //                             topology[old.circle].filter( c -> c.circle != c1);
  //                         }
  //                       i += 1;
  //                     }
  //                 }
  //             }
  //         }
  //     }
  // }

  function addTopology ()
  {
    topology = newTopology();
    var components:Map<Circle,Circle> = new Map();

    for (c1 in circles)
      {
        if (components[c1] == null)
          components[c1] = c1;

        var candidates = circles
          .filter( c -> c.radius < c1.radius && !lineIntersectsPath(c, c1) );

        candidates.sort( (a,b) -> Std.int(1000 * ptDist(a,c1)) - Std.int(1000 * ptDist(b, c1)));

        for (c2 in candidates.slice(0, subgraphSize))
          {
            components[c2] = components[c1];
            topology[c1].push({circle:c2, distance: ptDist(c2,c1)});
          }
      }

    for (c in circles)
      {
        var candidates = circles
          .filter( cand -> components[c] != components[cand]);

        if (candidates.length > 0)
          {
            candidates.sort(
                            (a,b) ->
                            Std.int(1000 * ptDist(a,c)) - Std.int(1000 * ptDist(b, c))
                            );
            
            var newConnect = candidates[0];
            var dist = ptDist( c, newConnect );
            topology[ c ].push( {circle:newConnect, distance: dist} );
            var comp = components[c];

            for ( z in components.keys() )
              if ( components[z] == comp )
                components[z] = components[newConnect];
          }
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
    animating = false;
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
    //graphics.beginFill(0);
    graphics.lineStyle(1,0xff0000);
    for (c in circles) drawCircle(c);
  }

  function drawTopology()
  {

    graphics.lineStyle(1,0x0000ff);
    for (pt in topology.keys()) {
      for (nbr in topology[pt]) {
        graphics.moveTo( pt.x, pt.y );      
        graphics.lineTo( nbr.circle.x, nbr.circle.y );
      }
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

    // graphics.moveTo( path[0].x,  path[0].y );

    // for (i in 1...path.length) {
    //   graphics.lineStyle(2, 0);
    //   graphics.lineTo( path[i].x, path[i].y );
    // }

    // graphics.lineStyle(2, 0);
    // graphics.lineTo(path[0].x, path[0].y);

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

  function pathIsCounterClockwise () : Bool
  {
    return path.length > 2 &&  isCounterClockwiseOrder(path[0],path[1],path[2]);
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

          if (pathIsCounterClockwise())
            path.reverse();

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
          
          animating = true;

          return; // exiting early.. a little ugly.
          
        case None: {}
        }      

      timestamp = stamp;
      path.push( pt );
      graphics.lineTo( e.localX, e.localY );
    }
    
  }

  var drift = {x: -0.5, y: 0.5};

  // function moveCircles ()
  // {
    
  // }

  function moveCircles ()
  {
    // var circ0 = circles[0];

    // var box = {
    // left: circ0.x - circ0.radius,
    // right: circ0.x + circ0.radius,
    // top: circ0.y - circ0.radius,
    // bottom: circ0.y + circ0.radius
    // };

    // var updateBox = (c:Circle) -> {
    //   box.left = Math.min( box.left, c.x - c.radius);
    //   box.right = Math.max( box.right, c.x + c.radius);
    //   box.top = Math.min( box.top, c.y - c.radius);
    //   box.bottom = Math.min( box.bottom , c.y + c.radius);
    // };
    
    // var time = Timer.stamp();
    // var sint = Math.sin( time );
    // var cost = Math.cos( time );

    // var newPositions = circles.map( c -> {
    //     updateBox( c );

    //     var newPos:Pt = { x:c.x, y:c.y };
    //     var nbrs = topology[c];

    //     newPos.x += ( drift.x * Math.cos( c.x / time) );
    //     newPos.y += ( drift.y * Math.sin( c.y / time) );

    //     for (n in nbrs) 
    //       if (n.radius < c.radius) {
    //         newPos.x += Math.cos( n.x / time);
    //         newPos.y += Math.sin( n.y / time);
    //       }

    //     return newPos;
    //   });

    // if (box.left <= 0 || box.right >= stage.stageWidth)
    //   drift.x *= -1;
    // if (box.top <= 0 || box.bottom >= stage.stageHeight)
    //   drift.y *= -1;
    
    // for (i in 0...circles.length) {
    //   circles[i].x = newPositions[i].x;
    //   circles[i].y = newPositions[i].y;
    // }
    
  }

  function perFrame (e)
  {
    // if (animating)
    //   {
    //     moveCircles();
    //     render();
    //   }
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
