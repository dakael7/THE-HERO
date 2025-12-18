import 'identity_model.dart';
import 'contact_model.dart';
import 'address_model.dart';
import 'hero_profile_model.dart';
import 'rider_profile_model.dart';
import 'user_status_model.dart';

class UserModel {
  final String id;
  final IdentityModel identity;
  final ContactModel contact;
  final AddressModel? address;
  final List<String> roles;
  final UserStatusModel status;
  final HeroProfileModel? heroProfile;
  final RiderProfileModel? riderProfile;

  UserModel({
    required this.id,
    required this.identity,
    required this.contact,
    this.address,
    required this.roles,
    required this.status,
    this.heroProfile,
    this.riderProfile,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String? ?? '',
      identity: IdentityModel.fromJson(
        json['identity'] as Map<String, dynamic>? ?? {},
      ),
      contact: ContactModel.fromJson(
        json['contact'] as Map<String, dynamic>? ?? {},
      ),
      address: json['address'] != null
          ? AddressModel.fromJson(json['address'] as Map<String, dynamic>)
          : null,
      roles: (json['roles'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? ['hero'],
      status: UserStatusModel.fromJson(
        json['status'] as Map<String, dynamic>? ?? {},
      ),
      heroProfile: json['heroProfile'] != null
          ? HeroProfileModel.fromJson(json['heroProfile'] as Map<String, dynamic>)
          : null,
      riderProfile: json['riderProfile'] != null
          ? RiderProfileModel.fromJson(json['riderProfile'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'identity': identity.toJson(),
      'contact': contact.toJson(),
      'address': address?.toJson(),
      'roles': roles,
      'status': status.toJson(),
      'heroProfile': heroProfile?.toJson(),
      'riderProfile': riderProfile?.toJson(),
    };
  }
}
