import Foundation

/// External links embedded in the app.
enum AppLinks {
    /// AWS account sign-up page (Japanese).
    static let awsSignUpURL = URL(string: "https://aws.amazon.com/jp/register-flow/")!

    /// CloudFormation quick-create link that builds the user's backend with
    /// one click. Points at the template published by
    /// backend/publish-template.ps1 — if you republish to a different bucket
    /// or region, update this URL too.
    static let backendQuickCreateURL = URL(
        string: "https://console.aws.amazon.com/cloudformation/home?region=ap-northeast-1#/stacks/quickcreate?templateURL=https%3A%2F%2Fphotouploader-templatebuilder.s3.ap-northeast-1.amazonaws.com%2Fphoto-uploader%2Ftemplate.yaml&stackName=photo-uploader"
    )!

    /// CloudFormation stack list in the AWS console — where the connection
    /// settings (the AppConfigJson stack output) can be re-checked any time
    /// after the backend is built.
    static let cloudFormationConsoleURL = URL(
        string: "https://console.aws.amazon.com/cloudformation/home?region=ap-northeast-1#/stacks"
    )!
}
