/// 用戶相關的數據模型

class UserModel {
  final int userId;
  final String username;
  final String email;

  UserModel({
    required this.userId,
    required this.username,
    required this.email,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      userId: json['user_id'],
      username: json['username'],
      email: json['email'],
    );
  }
}

class AuthResponse {
  final String accessToken;
  final String tokenType;
  final int userId;
  final String username;

  AuthResponse({
    required this.accessToken,
    required this.tokenType,
    required this.userId,
    required this.username,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      accessToken: json['access_token'],
      tokenType: json['token_type'] ?? 'bearer',
      userId: json['user_id'],
      username: json['username'],
    );
  }
}
