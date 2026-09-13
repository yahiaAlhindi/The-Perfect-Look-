/**
 * English locale for auth (T6).
 * The full app-wide namespace lands with T29 (localization).
 */

const en = {
  common: {
    appName: 'The Perfect Look',
    loading: 'Loading…',
    submitting: 'Please wait…',
    continue: 'Continue',
    submit: 'Submit',
    cancel: 'Cancel',
    back: 'Back',
    error: 'Something went wrong. Please try again.',
    confirm: 'Confirm',
  },

  auth: {
    languageLabel: 'Language',
    consentSectionLabel: 'Consent',

    // Shared links
    linkLogin: 'Sign in',
    linkRegister: 'Create an account',
    backToLogin: 'Back to sign in',
    alreadyHaveAccount: 'Already have an account?',
    noAccountYet: 'New to The Perfect Look?',

    // Validation messages shown inline next to fields
    validation: {
      fullNameRequired: 'Full name is required (min 2 characters)',
      emailInvalid: 'Please enter a valid email address',
      emailRequired: 'Email address is required',
      mobileInvalid:
        'Please enter a valid UAE mobile number (e.g. +971 5X XXX XXXX)',
      mobileRequired: 'Mobile number is required',
      passwordInvalid:
        'Password must be at least 8 characters and include uppercase, lowercase, number and special character',
      passwordRequired: 'Password is required',
      confirmPasswordMismatch: 'Passwords do not match',
      confirmPasswordRequired: 'Please confirm your password',
      consentRequired:
        'You must accept the required terms before creating your account',
    },

    // Friendly messages mapped from API error codes (T5 error catalog)
    apiError: {
      USER_EXISTS: 'An account with this email already exists.',
      DUPLICATE_ACCOUNT:
        'An account with this email or mobile number already exists.',
      INVALID_CREDENTIALS: 'Incorrect email or password.',
      EMAIL_NOT_CONFIRMED:
        'Please verify your email address before signing in.',
      WEAK_PASSWORD:
        'Password must be at least 8 characters and include uppercase, lowercase, number and special character.',
      INVALID_EMAIL: 'Please enter a valid email address.',
      SIGNUP_DISABLED: 'Registration is currently unavailable.',
      RATE_LIMITED: 'Too many requests. Please try again in a minute.',
      SAME_PASSWORD: 'New password must be different from the current one.',
      INVALID_IDENTIFIER: 'Enter a valid email address or mobile number.',
      UNKNOWN: 'Something went wrong. Please try again.',
    },

    register: {
      title: 'Create your account',
      subtitle:
        'Sign up in under a minute and book appointments at The Perfect Look.',
      fullName: 'Full name',
      fullNamePlaceholder: 'e.g. Aisha Al Marzooqi',
      email: 'Email address',
      emailPlaceholder: 'you@example.com',
      mobile: 'Mobile number',
      mobilePlaceholder: '+971 5X XXX XXXX',
      password: 'Password',
      passwordPlaceholder: 'Min 8 chars with a number and special character',
      confirmPassword: 'Confirm password',
      confirmPasswordPlaceholder: 'Re-enter your password',
      passwordHint:
        'Min 8 characters with uppercase, lowercase, number and special character',
      preferredLanguage: 'Preferred language',
      dob: 'Date of birth',
      dobOptional: 'Date of birth (optional)',
      gender: 'Gender',
      genderOptional: 'Gender (optional)',
      selectGender: 'Select…',
      genderFemale: 'Female',
      genderMale: 'Male',
      genderUnspecified: 'Prefer not to say',
      consentService:
        'I agree to the Terms of Service, Privacy Policy and health-data handling.',
      consentServiceRequired: 'Required',
      consentMarketing: 'I agree to receive promotional offers and news by email or SMS.',
      consentMarketingOptional: 'Optional',
      submit: 'Create account',
      successTitle: 'Your account was created',
      successBody:
        'Please check your email to verify your account, then sign in to continue.',
      clientNumberLabel: 'Your client number',
      clientNumberPlaceholder: '—',
      clientNumberNote:
        'Your client number will appear here once your account is fully set up.',
      backToHome: 'Go to home',
    },

    login: {
      title: 'Sign in',
      subtitle: 'Book appointments, view schedules and manage your visits.',
      identifier: 'Email or mobile number',
      identifierPlaceholder: 'you@example.com or +971 5X XXX XXXX',
      password: 'Password',
      passwordPlaceholder: 'Enter your password',
      showPassword: 'Show password',
      hidePassword: 'Hide password',
      forgotPassword: 'Forgot your password?',
      submit: 'Sign in',
      continueToBooking: 'Continue booking',
      returningToBooking: 'You will go back to where you left off after signing in.',
      noAccount: 'New to The Perfect Look?',
    },

    forgot: {
      title: 'Reset your password',
      subtitle:
        'Enter the email address linked to your account and we will send you a reset link.',
      email: 'Email address',
      emailPlaceholder: 'you@example.com',
      submit: 'Send reset link',
      sentTitle: 'Check your email',
      sentBody:
        'If an account exists for this address, a password reset link has been sent.',
      sentSpamNote: 'It can take a few minutes. Also check your spam folder.',
    },

    reset: {
      title: 'Choose a new password',
      subtitle:
        'Your reset link has been verified. Enter a new password below.',
      password: 'New password',
      passwordPlaceholder: 'Min 8 chars with a number and special character',
      confirmPassword: 'Confirm new password',
      confirmPasswordPlaceholder: 'Re-enter your new password',
      passwordHint:
        'Min 8 characters with uppercase, lowercase, number and special character',
      submit: 'Update password',
      successTitle: 'Password updated',
      successBody: 'You can now sign in with your new password.',
      goToLogin: 'Go to sign in',
      invalidTitle: 'Link invalid or expired',
      invalidBody:
        'This password reset link is no longer valid. Request a new one to continue.',
      requestNewLink: 'Request a new link',
    },

    logout: {
      title: 'Sign out',
      confirmBody: 'Are you sure you want to sign out?',
      confirmButton: 'Sign out',
      cancelButton: 'Cancel',
      doneTitle: 'You have been signed out',
      doneBody: 'Come back anytime to book your next appointment.',
      goToLogin: 'Sign in again',
    },
  },

  profile: {
    title: 'My account',
    subtitle: 'Manage your personal details, preferences and privacy choices.',
    backHome: 'Back to home',
    signOut: 'Sign out',

    detailsTitle: 'Personal details',
    detailsIntro:
      'These details appear on your appointment records. Email and mobile number are changed only after verification.',
    fullName: 'Full name',
    fullNamePlaceholder: 'e.g. Aisha Al Marzooqi',
    email: 'Email address',
    mobile: 'Mobile number',
    clientNumber: 'Client number',
    clientNumberPlaceholder: '—',
    clientNumberNote: 'Issued by the clinic when your record is complete.',
    dob: 'Date of birth',
    dobEmpty: 'Not provided',
    gender: 'Gender',
    selectGender: 'Select…',
    genderFemale: 'Female',
    genderMale: 'Male',
    genderUnspecified: 'Prefer not to say',
    preferredLanguage: 'Preferred language',
    save: 'Save changes',
    saved: 'Your details were saved.',
    saveFailed: 'We could not save your details. Please try again.',

    consentTitle: 'Consent preferences',
    consentIntro:
      'Review how your information is used and manage your marketing choices. Every change is recorded with a date and version (SRS §17).',
    consentService: 'Terms of Service & Privacy Policy',
    consentServiceMeta: 'Accepted — version {{version}}, {{date}}',
    consentServiceNotice: 'This agreement is required for your account.',
    consentMarketing: 'Marketing & promotions',
    consentMarketingOn:
      'You receive promotional offers and news by email or SMS.',
    consentMarketingOff:
      'You have opted out of promotional messages.',
    consentMarketingNotSet:
      'You have not set a marketing preference yet.',
    allowMarketing:
      'I agree to receive promotional offers and news by email or SMS.',
    marketingHint:
      'You can change this anytime. Your decision is recorded with a timestamp.',
    consentFailed: 'We could not save this change. Please try again.',
    historyTitle: 'Consent history',
    historyEmpty: 'No consent records yet.',
    viewHistory: 'View history',
    historyGranted: 'Granted',
    historyWithdrawn: 'Withdrawn',

    dataTitle: 'Your data',
    dataIntro: 'You are in control of your information.',
    requestData: 'Request a copy of my data',
    requestDataSent:
      'Your request was received. The clinic will contact you when your data is ready.',
    requestDataFailed:
      'We could not submit your request. Please try again.',
    nutritionNoticeTitle: 'Health & nutrition records',
    nutritionNoticeBody:
      'Your nutrition assessment and health records are stored and protected separately. View them in the nutrition section.',
    dataPrivacyNote:
      'Requests are fulfilled within the timeframes required by UAE data protection law.',

    passwordTitle: 'Password',
    passwordIntro: 'Change the password you use to sign in.',
    currentPassword: 'Current password',
    currentPasswordPlaceholder: 'Enter your current password',
    newPassword: 'New password',
    newPasswordPlaceholder: 'Min 8 chars with a number and special character',
    confirmPassword: 'Confirm new password',
    confirmPasswordPlaceholder: 'Re-enter your new password',
    passwordHint:
      'Min 8 characters with uppercase, lowercase, number and special character',
    changePassword: 'Change password',
    passwordChanged: 'Your password was updated.',
    passwordChangeFailed: 'We could not change your password.',

    apiError: {
      NOT_AUTHENTICATED: 'Your session has expired. Please sign in again.',
      SAME_PASSWORD:
        'New password must be different from the current one.',
      INVALID_CREDENTIALS: 'The current password you entered is incorrect.',
      WEAK_PASSWORD:
        'New password must be at least 8 characters and include uppercase, lowercase, number and special character.',
      UNKNOWN: 'Something went wrong. Please try again.',
    },
  },
}

export default en