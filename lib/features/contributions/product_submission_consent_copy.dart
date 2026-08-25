/// Pinned privacy and consent language shared by both product-evidence flows.
/// Keep these strings vendor-neutral: the extraction provider may change,
/// while the disclosure and human-approval guarantees must not.
const missingProductPrivacyCopy =
    'Your account identifier, this barcode, and selected product-label '
    'photos go privately to PharmaGuide for review. We strip embedded photo '
    'metadata (EXIF) before upload, but anything visible in the pixels '
    'remains. Do not include pharmacy stickers, names, prescription numbers, '
    'or other personal health information.\n\n'
    'A third-party AI service may read the label to prepare a draft. A human '
    'reviewer approves every catalog entry. If approved, the front-label '
    'photo—including a crop—may be published as the product image. Your '
    'health profile, medications, conditions, allergies, and stack stay on '
    'this device.';

const missingProductConsentCopy =
    'I consent to send this account-linked product submission, barcode, and '
    'selected label photos privately to PharmaGuide for review. A '
    'third-party AI service may read the label, but a human reviewer approves '
    'every entry. If approved, the front-label photo—including a crop—may be '
    'published as the product image. I confirm the photos contain no pharmacy '
    'stickers or other personal health information.';

const labelMismatchPrivacyCopy =
    'Your account identifier, this product’s catalog identifiers (including '
    'UPC when available), selected mismatch categories, and selected '
    'product-label photos go privately to PharmaGuide for review. We strip '
    'embedded photo metadata (EXIF) before upload, but anything visible in '
    'the pixels remains. Do not include pharmacy stickers, names, '
    'prescription numbers, or other personal health information.\n\n'
    'A third-party AI service may read the label to prepare a draft. A human '
    'reviewer approves every catalog entry. If approved, the front-label '
    'photo—including a crop—may be published as the product image. Your '
    'health profile, medications, conditions, allergies, and stack stay on '
    'this device.';

const labelMismatchConsentCopy =
    'I consent to send this account-linked product report, its catalog '
    'identifiers, selected mismatch categories, and selected label photos '
    'privately to PharmaGuide for review. A third-party AI service may read '
    'the label, but a human reviewer approves every entry. If approved, the '
    'front-label photo—including a crop—may be published as the product '
    'image. I confirm the photos contain no pharmacy stickers or other '
    'personal health information.';
