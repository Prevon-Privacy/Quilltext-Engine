import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:flutter/material.dart';

mixin BlockComponentAlignMixin {
  Node get node;

  Alignment? get alignment {
    final alignString = node.attributes[blockComponentAlign] as String?;
    switch (alignString) {
      case 'center':
        return Alignment.center;
      case 'right':
        return Alignment.centerRight;
      case 'left':
        return Alignment.centerLeft;
      default:
        return null;
    }
  }
}
