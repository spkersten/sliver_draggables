import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:sliver_draggables/sliver_reorderable_grid.dart';

void main() {
  runApp(SliverReorderableExample());
}

class SliverReorderableExample extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sliver reorderable example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: Example(),
    );
  }
}

class Example extends StatefulWidget {
  @override
  _ExampleState createState() => _ExampleState();
}

class _ExampleState extends State<Example> {
  var _items = List.generate(10, (index) => index);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Sliver reorderable example")),
      body: CustomScrollView(
        scrollDirection: Axis.horizontal,
        slivers: [
          SliverPadding(
            padding: EdgeInsets.all(8),
            sliver: SliverLongPressReorderableGrid(
              delegate: SliverChildListDelegate(
                _items
                    .map((item) => Material(
                          color: Colors.transparent,
                          child: Container(
                            decoration: BoxDecoration(
                              boxShadow: [BoxShadow(blurRadius: 8, offset: Offset(0, 5), color: Colors.black54)],
                              color: Colors.red,
                            ),
                            alignment: Alignment.center,
                            child: Text("$item", style: TextStyle(fontSize: 40, color: Colors.white38)),
                          ),
                        ))
                    .toList(growable: false),
                addAutomaticKeepAlives: false,
              ),
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 120,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              onReorder: (sourceIndex, targetIndex) {
                setState(() {
                  final clampedTarget = targetIndex.clamp(0, _items.length - 1).toInt();
                  final movee = _items.removeAt(sourceIndex);
                  _items.insert(clampedTarget, movee);
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}
