import 'package:flutter/material.dart';
import '../../widgets/widgets.dart';

/// Replaced by the Feed compose screen in the Feed milestone.
class ComposePlaceholder extends StatelessWidget {
  const ComposePlaceholder({super.key, this.text});
  final String? text;
  @override
  Widget build(BuildContext context) => KeysScaffold(
        header: const KeysHeader(),
        body: Intro(title: 'Create post', body: text ?? ''),
      );
}
