### EventBridge for WorkSpaces Creation
resource "aws_cloudwatch_event_rule" "creation" {
  event_bus_name = "default"
  name           = "CreateWorkSpacesRule"

  description = "Calls AWS Lambda that will be responsible to create Workspaces and users in domain."

  event_pattern = templatefile("./templates/event-rule-instance-creation.json.j2",{
      aws_s3_bucket_lambda_bucket_name = "${aws_s3_bucket.workspaces_creation_bucket.id}"
  })
}

resource "aws_cloudwatch_event_target" "creation" {
  event_bus_name = "default"
  rule           = aws_cloudwatch_event_rule.creation.name
  target_id      = "eventlambda"
  arn            = aws_lambda_function.lambda_creation.arn
  #role_arn       = aws_iam_role.events_to_sm.arn

  #dead_letter_config {
  #  arn = aws_sqs_queue.arn
  #}

  retry_policy {
    maximum_retry_attempts       = 6
    maximum_event_age_in_seconds = 180
  }
}

resource "aws_lambda_permission" "allow_eventbridge_creation_call_lambda" {
  statement_id = "AllowExecutionFromCloudWatch"
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_creation.function_name
  principal = "events.amazonaws.com"
  source_arn = aws_cloudwatch_event_rule.creation.arn
}

### EventBridge for WorkSpaces Termination
resource "aws_cloudwatch_event_rule" "this" {
  event_bus_name = "default"
  name           = "TerminateWorkSpacesRule"

  description = "Calls AWS Lambda that will be responsible to remove a machine for the domain when an WorkSpace instance is terminated."

  event_pattern = templatefile("./templates/event-rule-instance-termination.json.j2",{})

}

resource "aws_cloudwatch_event_target" "this" {
  event_bus_name = "default"
  rule           = aws_cloudwatch_event_rule.this.name
  target_id      = "eventlambda"
  arn            = aws_lambda_function.lambda.arn
  #role_arn       = aws_iam_role.events_to_sm.arn

  #dead_letter_config {
  #  arn = aws_sqs_queue.arn
  #}

  retry_policy {
    maximum_retry_attempts       = 6
    maximum_event_age_in_seconds = 180
  }
}

resource "aws_lambda_permission" "allow_eventbridge_termination_call_lambda" {
  statement_id = "AllowExecutionFromCloudWatch"
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda.function_name
  principal = "events.amazonaws.com"
  source_arn = aws_cloudwatch_event_rule.this.arn
}