.fields | map({ key: .label, value: .value }) | from_entries | {
    auths: {
        "ghcr.io": {
            username: "\(.username)",
            password: "\(.password)",
            email: "\(.email)",
            auth: "\(.username):\(.password)" | @base64
        }
    }
}
