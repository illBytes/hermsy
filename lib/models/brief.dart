/// The Brief: the day at a glance, written by the "Hermsy Brief" job.
class Brief {
  const Brief({
    required this.id,
    required this.createdAt,
    required this.sections,
    this.greeting,
    this.headline,
    this.summary,
  });

  final String id;
  final DateTime createdAt;
  final String? greeting;

  /// The single most important thing right now.
  final String? headline;
  final String? summary;
  final List<BriefSection> sections;

  BriefSection? section(String id) {
    for (final section in sections) {
      if (section.id == id) {
        return section;
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'created_at': createdAt.toUtc().toIso8601String(),
    'greeting': greeting,
    'headline': headline,
    'summary': summary,
    'sections': [
      for (final section in sections)
        {
          'id': section.id,
          'title': section.title,
          'items': [
            for (final item in section.items)
              {
                'title': item.title,
                'detail': ?item.detail,
                'time': ?item.time,
                'when': ?item.when,
                'action': ?item.action,
              },
          ],
        },
    ],
  };

  factory Brief.fromJson(Map<String, dynamic> json) {
    return Brief(
      id: json['id'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      greeting: json['greeting'] as String?,
      headline: json['headline'] as String?,
      summary: json['summary'] as String?,
      sections: [
        for (final raw in json['sections'] as List? ?? const [])
          if (raw is Map<String, dynamic>) BriefSection.fromJson(raw),
      ],
    );
  }
}

/// One card of the brief: today, due, suggestions, coming up, money.
class BriefSection {
  const BriefSection({
    required this.id,
    required this.title,
    required this.items,
  });

  final String id;
  final String title;
  final List<BriefItem> items;

  factory BriefSection.fromJson(Map<String, dynamic> json) {
    return BriefSection(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      items: [
        for (final raw in json['items'] as List? ?? const [])
          if (raw is Map<String, dynamic>) BriefItem.fromJson(raw),
      ],
    );
  }
}

class BriefItem {
  const BriefItem({
    required this.title,
    this.detail,
    this.time,
    this.when,
    this.action,
  });

  final String title;
  final String? detail;

  /// "16:00", for timed items today.
  final String? time;

  /// "Tomorrow", "Overdue", "In 3 days".
  final String? when;

  /// What Frank will do if you say yes (suggestions).
  final String? action;

  bool get overdue => when?.toLowerCase().contains('overdue') ?? false;

  factory BriefItem.fromJson(Map<String, dynamic> json) {
    return BriefItem(
      title: json['title'] as String? ?? '',
      detail: json['detail'] as String?,
      time: json['time'] as String?,
      when: json['when'] as String?,
      action: json['action'] as String?,
    );
  }
}

/// The sections the Brief can show, in their default order.
const briefSectionIds = <String>[
  'today',
  'due',
  'suggestions',
  'coming_up',
  'money',
  'updates',
];

const briefSectionNames = <String, String>{
  'today': 'Today',
  'due': 'Due soon',
  'suggestions': 'Suggestions',
  'coming_up': 'Coming up',
  'money': 'Money',
  'updates': 'Updates from Hermsy',
};
