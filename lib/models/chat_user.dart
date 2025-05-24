class ChatUser {
  final String id;
  final String name;
  final String email;
  final String? photo;

  ChatUser({
    required this.id,
    required this.name,
    required this.email,
    this.photo,
  });

  factory ChatUser.fromMap(Map<String, dynamic> map) {
    return ChatUser(
      id: map['id'],
      name: map['name'],
      email: map['email'],
      photo: map['photo'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'photo': photo,
    };
  }
}
