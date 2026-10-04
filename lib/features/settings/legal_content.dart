// ---------------------------------------------------------------------------
// Live privacy policy + EULA copy, written for what this app actually does
// (confirmed against real permission declarations and data flows, not
// guessed): Supabase-hosted photos/posts, the anonymous feed and its
// separate persona, Duos, groups and circles, date of
// birth collected once at signup, in-app reporting and blocking, and
// account deletion. No location, contacts, or analytics/crash-reporting SDK
// is used anywhere in the app — deliberately not mentioned below since
// nothing would be true to say about them.
//
// MIRROR, NOT SOURCE OF TRUTH: the authoritative copies are the hosted
// pages at AppStrings.privacyPolicyUrl / AppStrings.eulaUrl (Netlify) —
// that is what the Play Console Data Safety form points at and what signup
// links to, because a store reviewer needs a URL they can open without
// installing the app. This file is the offline-readable in-app mirror.
// If either changes, BOTH change together.
//
// 2026-09-20 correction pass — four things here were factually wrong
// against shipped behaviour, found by auditing the code rather than
// re-reading the policy:
//   1. Date of birth was collected at onboarding (onboarding_screen.dart's
//      _birthDate -> set_my_birth_date RPC) and §1 did not mention it at
//      all — the most sensitive field in the list, unlisted.
//   2. Deletion was described as soft-delete only ("prevents you from
//      signing back in"). The delete-account function was since rewritten
//      to also delete pings/ping replies and device tokens, purge storage
//      objects, and scrub PII. The policy understated what actually
//      happens.
//   3. prompt_impressions (per-user, per-prompt view counts + timestamps,
//      which drive prompt ranking) was not described.
//   4. Circles — private, silent posting audiences — did not exist when
//      the EULA's content-licence section was written.
//
// 2026-09-27 pass — caught up with what shipped since: circles replaced
// friend requests, Duo photos need both people's approval (either can lock
// it back to private), group posts carry a typed place + date, group QR join
// codes, RealMoji selfies (one reaction per post, newest wins), seen/"here"
// viewer records, scores/levels/leaderboards, anonymous pings, on-device
// face filters, and the two service providers (Supabase, FCM) named.
// ---------------------------------------------------------------------------

const String kPrivacyPolicyBody = '''
Last updated: September 27, 2026

This Privacy Policy describes how the developer of this app ("we", "us") handles information when you use it.

1. INFORMATION WE COLLECT
• Account information: your email address, display name, username, bio, and profile and banner photos.
• Date of birth: collected once during sign-up, used only to determine whether your account belongs to a minor for age-appropriate content rules and store compliance. It is never shown on your profile, never shown to other users, and is not used for any other purpose. It is stored with database-level restrictions that prevent it from being read by anyone other than you.
• Content you create: posts, moments, comments, reactions, pings and ping replies, and photos you upload — including anonymous-feed posts, which are stored under a separate anonymous persona name rather than your real name.
• Photos and media you upload to Duos (shared albums), group posts, and your profile.
• RealMoji selfies: when you react with a RealMoji, the selfie you take is saved to your account so you can reuse it, and it is shown to the people who can see the post you reacted to. You can retake it at any time. You keep one reaction per post — a new reaction replaces your previous one.
• Group post details: group posts include a caption, a note, a place name you type in, and the date the moment was taken. The place is text you enter; the app does not read your device's location.
• Post views and presence: when you open a post, we record that you viewed it. This powers the "seen" and "here now" indicators described in section 5.
• Profile views: when you visit someone's profile, that visit is recorded against your account and the profile owner is sent a notification that someone viewed them. By default your name is not included in that notification — see "How we use information" below for when it is.
• Scores and streaks: points, levels, and streaks you earn by posting, reacting, commenting, and answering pings.
• Usage information: which posts you view, react to, or comment on, and basic device/session information needed to operate push notifications.
• Prompt activity: a record of which daily prompts have been shown to you, how many times, and when. This is used to avoid repeatedly showing you the same prompt and to decide which prompt to surface next. It is tied to your account and is not shown to other users.
• Relationship information: the circles you create and who you put in them, your Duos, group memberships, invites and join codes, and the people you choose to block.

We do not collect your location, access your contacts, or use any third-party analytics or advertising SDK. The camera, microphone, and photo library permissions this app requests are used only for the features above — capturing and uploading photos/video you choose to post or send. The camera's face filters use on-device face detection to position effects on your face.

2. HOW WE USE INFORMATION
• To operate the app's core features — feeds, groups, Duos, circles, pings, and notifications.
• To choose which daily prompt to show you, using the prompt activity described above.
• To calculate scores, levels, streaks, and leaderboards.
• To enforce blocking: if you block someone, their named content is hidden from you and yours from them, and neither of you appears in the other's search results.
• To send push notifications for activity relevant to you (pings, reactions, comments, Duo and group invites, reminders, and profile views). Every profile view sends the owner a notification. If you have not pinned the viewer, that notification says only "Someone's viewing you right now" — their identity is withheld. If you have pinned them, it names them, and additionally tells you whether they are viewing your profile live at that moment.
• To investigate reports of abuse and enforce our terms.

3. THE ANONYMOUS FEED AND ANONYMOUS PINGS
Posts to the anonymous feed are shown under a separate anonymous persona, not your real name, and are posted into a shared feed — this app has no 1:1 anonymous-chat feature and does not connect you privately with strangers. Pings sent from a post are delivered without showing the recipient who sent them. We nonetheless retain an internal link between your account and your anonymous posts and pings for moderation and safety purposes; this link is not shown to other users.

4. CIRCLES AND FRIENDS
There are no friend requests. Your "Friends" are the people you put in your Friends circle, and you decide this on your own — adding someone does not add you to theirs. You can also create other circles (such as Close Friends or Family) and post to them. Circle membership is deliberately one-sided: only the person who created the circle can see that it exists or who is in it. If you are added to someone's circle you are not notified, and you cannot see the circle, its name, or its other members. You may see a post that reached you through a circle without being told that is why. A post shared to your friends reaches only the circles you pick, or your Friends circle if you don't pick any.

5. WHAT OTHER PEOPLE CAN SEE
• Your posts are shown only to the audience you choose when posting.
• Who has seen a post: the author of a post can see who has viewed it, and people viewing a post can see who else is currently on it.
• Reactions: the people who reacted to a post, with their RealMoji selfies, can be viewed on the post author's profile or the group's profile.
• Scores, levels, and streaks may be shown on your posts, your profile, and leaderboards.
• Duos: a photo added to a Duo is posted only after both of you approve it, each choosing your own audience, and it is then shown to both audiences. Either of you can make a Duo photo private again at any time, which removes it from every feed, or delete it.
• Groups: posts in a group are visible to its members. Any member may share a group post with their own audience. A private group's posts may also appear to members of its communities with only the first photo visible and no comments. Anyone holding a group's QR join code can use it to join that group, so share it only with people you want in the group.

6. REPORTING AND MODERATION
Every post and comment can be reported in-app. Reports are reviewed by moderators, who may remove the content and, where applicable, suspend the responsible account. If you submit a report, you'll receive a notification once it's been reviewed, letting you know whether the content was removed.

7. SHARING AND SERVICE PROVIDERS
We do not sell your personal information. Content you post to shared or group spaces is visible to the people in those spaces, per the visibility you choose when posting. Your account data and uploads are stored with our hosting provider (Supabase), and push notifications are delivered through Firebase Cloud Messaging; these providers process data only to run those services for us. We may disclose information if required by law or to protect the safety of our users.

8. DATA RETENTION AND DELETION
You can permanently delete your account and content at any time from Settings → Delete Account. When you do, we:
• Delete the pings and ping replies you sent or received.
• Delete the device tokens used to send you push notifications, so notifications stop immediately.
• Delete the photos and media you uploaded from our storage.
• Remove your personal details from your account record — your email address, name, username, anonymous persona name, date of birth, and profile and banner photos are erased or replaced with non-identifying placeholders.
• Mark your account as deleted and prevent you from signing back in.

Content you posted into shared spaces may remain visible to others where removing it would break another person's record of a shared moment, and previously reported content may be retained in a form accessible to moderators so that reports can still be reviewed. Some information may also be retained where required for legal, safety, or fraud-prevention purposes.

9. YOUR CHOICES
You can edit your profile name and bio, change who is in your circles, choose the audience of each post, make a Duo photo private, retake or change your RealMoji selfies, block or unblock other users, report content, and delete your account at any time from Settings.

10. CONTACT
Questions about this policy: abisheksdpatel@gmail.com.
''';

const String kEulaBody = '''
Last updated: September 27, 2026

END USER LICENSE AGREEMENT

This End User License Agreement ("Agreement") governs your use of this app, provided by its developer ("we", "us"). By creating an account or using the app, you agree to this Agreement.

1. LICENSE
Subject to this Agreement, we grant you a limited, non-exclusive, non-transferable, revocable license to use the app for your personal, non-commercial use.

2. ELIGIBILITY
You must provide your date of birth when you create an account, and it must be accurate. We use it only to apply age-appropriate rules to your account. If you are below the minimum age for your country, you may not use this app.

3. YOUR CONTENT
You retain ownership of content you post (photos, posts, comments, reactions). By posting, you grant us a license to store, display, and distribute that content within the app as necessary to operate its features — feeds, groups, shared albums, circles, and notifications — and to show it to exactly the audience you selected when posting, whether that is your friends, a community, a group, a Duo, or a circle. A Duo photo is shown only once both people in the Duo have approved it, and either of you can make it private again.

4. CONDUCT
You agree not to:
• Harass, threaten, or abuse other users.
• Post content that is illegal, hateful, or infringes someone else's rights.
• Attempt to circumvent blocking, reporting, or moderation features.
• Use the anonymous feed to target or identify a specific person without their consent.
• Use circles to collect or redistribute another person's content outside the audience they chose.
• Share a group's QR join code, or a group post, in a way that exposes other members against their wishes.
• Manipulate scores, streaks, or leaderboards through automated or abusive activity.

Violations may result in content removal, account suspension, or account deletion.

5. REPORTING, BLOCKING AND MODERATION
Every post and comment can be reported in-app, and any user can be blocked — blocking hides their named content from you and yours from them across the app. We review reports and may remove content or suspend accounts at our discretion; a reporter is notified once their report has been reviewed.

6. ACCOUNT DELETION
You may permanently delete your account at any time from Settings → Delete Account. Deletion removes your pings and ping replies, your push notification device tokens, and the photos and media you uploaded; erases or replaces your personal details (email address, name, username, anonymous persona name, date of birth, and profile and banner photos); and prevents you from signing back in. Some data may be retained as described in our Privacy Policy, including previously reported content kept available to moderators.

7. DISCLAIMER AND LIABILITY
The app is provided "as is" without warranties of any kind. To the maximum extent permitted by law, the developer is not liable for indirect, incidental, or consequential damages arising from your use of the app.

8. CHANGES
We may update this Agreement from time to time. Continued use of the app after changes take effect constitutes acceptance of the revised Agreement.

9. CONTACT
Questions about this Agreement: abisheksdpatel@gmail.com.
''';
