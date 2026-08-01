enum PatientRequestStatus {
  pendingReview,
  accepted,
  enRoute,
  arrived,
  inService,
  completed,
  rejected,
  cancelled,
}

enum HomeRouteTarget { none, underReview, tracking }

extension PatientRequestStatusX on PatientRequestStatus {
  bool get isActive {
    switch (this) {
      case PatientRequestStatus.pendingReview:
      case PatientRequestStatus.accepted:
      case PatientRequestStatus.enRoute:
      case PatientRequestStatus.arrived:
      case PatientRequestStatus.inService:
        return true;
      case PatientRequestStatus.completed:
      case PatientRequestStatus.rejected:
      case PatientRequestStatus.cancelled:
        return false;
    }
  }

  HomeRouteTarget get homeRouteTarget {
    switch (this) {
      case PatientRequestStatus.pendingReview:
      case PatientRequestStatus.accepted:
        return HomeRouteTarget.underReview;
      case PatientRequestStatus.enRoute:
      case PatientRequestStatus.arrived:
      case PatientRequestStatus.inService:
        return HomeRouteTarget.tracking;
      case PatientRequestStatus.completed:
      case PatientRequestStatus.rejected:
      case PatientRequestStatus.cancelled:
        return HomeRouteTarget.none;
    }
  }

  String get labelEn {
    switch (this) {
      case PatientRequestStatus.pendingReview:
        return 'Under review';
      case PatientRequestStatus.accepted:
        return 'Doctor assigned';
      case PatientRequestStatus.enRoute:
        return 'On the way';
      case PatientRequestStatus.arrived:
        return 'Arrived';
      case PatientRequestStatus.inService:
        return 'In service';
      case PatientRequestStatus.completed:
        return 'Completed';
      case PatientRequestStatus.rejected:
        return 'Rejected';
      case PatientRequestStatus.cancelled:
        return 'Cancelled';
    }
  }

  String get labelBn {
    switch (this) {
      case PatientRequestStatus.pendingReview:
        return 'পর্যালোচনায়';
      case PatientRequestStatus.accepted:
        return 'ডাক্তার নির্ধারিত';
      case PatientRequestStatus.enRoute:
        return 'পথে আছেন';
      case PatientRequestStatus.arrived:
        return 'পৌঁছেছেন';
      case PatientRequestStatus.inService:
        return 'সেবা চলছে';
      case PatientRequestStatus.completed:
        return 'সম্পন্ন';
      case PatientRequestStatus.rejected:
        return 'প্রত্যাখ্যাত';
      case PatientRequestStatus.cancelled:
        return 'বাতিল';
    }
  }

  String toWire() {
    switch (this) {
      case PatientRequestStatus.pendingReview:
        return 'pending_review';
      case PatientRequestStatus.accepted:
        return 'accepted';
      case PatientRequestStatus.enRoute:
        return 'en_route';
      case PatientRequestStatus.arrived:
        return 'arrived';
      case PatientRequestStatus.inService:
        return 'in_service';
      case PatientRequestStatus.completed:
        return 'completed';
      case PatientRequestStatus.rejected:
        return 'rejected';
      case PatientRequestStatus.cancelled:
        return 'cancelled';
    }
  }

  static PatientRequestStatus fromWire(String? raw) {
    switch (raw?.toLowerCase().replaceAll('-', '_')) {
      case 'pending_review':
      case 'pending':
        return PatientRequestStatus.pendingReview;
      case 'accepted':
      case 'assigned':
        return PatientRequestStatus.accepted;
      case 'en_route':
      case 'enroute':
      case 'on_the_way':
        return PatientRequestStatus.enRoute;
      case 'arrived':
        return PatientRequestStatus.arrived;
      case 'in_service':
      case 'in_progress':
        return PatientRequestStatus.inService;
      // Service finished but the balance is still due (and the nurse
      // hand-off state while the doctor owes the prescription). Both map
      // to the review bucket so `homeRouteTarget` routes the patient off
      // the Tracking tab and back to the booking surface, where the
      // invoice + pay-balance card renders.
      case 'service_completed_awaiting_final_payment':
      case 'nurse_completed':
        return PatientRequestStatus.pendingReview;
      case 'completed':
        return PatientRequestStatus.completed;
      case 'rejected':
        return PatientRequestStatus.rejected;
      case 'cancelled':
      case 'canceled':
        return PatientRequestStatus.cancelled;
      default:
        return PatientRequestStatus.pendingReview;
    }
  }
}
