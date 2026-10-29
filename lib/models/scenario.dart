enum Level { beginner, intermediate, advanced }

extension LevelText on Level {
  String get label => switch (this) {
        Level.beginner => 'Beginner',
        Level.intermediate => 'Intermediate',
        Level.advanced => 'Advanced',
      };

  String get hint => switch (this) {
        Level.beginner => 'Short, simple phrases',
        Level.intermediate => 'Full sentences',
        Level.advanced => 'Natural speed and idioms',
      };
}

class Scenario {
  const Scenario(this.id, this.rw, this.en);

  /// Must match a key in backend/prompt.js SCENARIOS.
  final String id;
  final String rw;
  final String en;
}

const scenarios = <Scenario>[
  Scenario('greet', 'Kuramukanya', 'Greetings and introductions'),
  Scenario('market', 'Ku isoko', 'At the market'),
  Scenario('moto', 'Kuri moto', 'Taking a moto'),
  Scenario('food', 'Muri resitora', 'At a restaurant'),
  Scenario('family', 'Umuryango', 'Talking about family'),
  Scenario('free', 'Ikiganiro gisanzwe', 'Free conversation'),
];
