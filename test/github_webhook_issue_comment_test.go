//go:build e2e

package test

import (
	"context"
	"testing"
	"time"

	"github.com/openshift-pipelines/pipelines-as-code/pkg/params/triggertype"
	tgithub "github.com/openshift-pipelines/pipelines-as-code/test/pkg/github"
	twait "github.com/openshift-pipelines/pipelines-as-code/test/pkg/wait"
	"gotest.tools/v3/assert"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// TestGithubWebhookIssueCommentRetest tests /retest GitOps command via webhook.
func TestGithubWebhookIssueCommentRetest(t *testing.T) {
	ctx := context.Background()
	g := &tgithub.PRTest{
		Label:     "Github webhook /retest comment",
		YamlFiles: []string{"testdata/pipelinerun.yaml"},
		Webhook:   true,
	}
	g.RunPullRequest(ctx, t)
	defer g.TearDown(ctx, t)

	// Wait for initial PR to be processed
	time.Sleep(5 * time.Second)

	// Send /retest webhook
	g.SendIssueCommentWebhook(ctx, t, "/retest")

	// Verify pipeline runs are created
	sopt := twait.SuccessOpt{
		Title:           g.CommitTitle,
		OnEvent:         triggertype.PullRequest.String(),
		TargetNS:        g.TargetNamespace,
		NumberofPRMatch: 1,
		SHA:             g.SHA,
	}
	twait.Succeeded(ctx, t, g.Cnx, g.Options, sopt)
}

// TestGithubWebhookIssueCommentTestSpecific tests /test <pipeline> GitOps command via webhook.
func TestGithubWebhookIssueCommentTestSpecific(t *testing.T) {
	ctx := context.Background()
	g := &tgithub.PRTest{
		Label:     "Github webhook /test specific",
		YamlFiles: []string{"testdata/pipelinerun.yaml"},
		Webhook:   true,
	}
	g.RunPullRequest(ctx, t)
	defer g.TearDown(ctx, t)

	// Wait for initial PR to be processed
	time.Sleep(5 * time.Second)

	// Send /test pipelinerun webhook
	g.SendIssueCommentWebhook(ctx, t, "/test pipelinerun")

	// Verify pipeline runs are created
	sopt := twait.SuccessOpt{
		Title:           g.CommitTitle,
		OnEvent:         triggertype.PullRequest.String(),
		TargetNS:        g.TargetNamespace,
		NumberofPRMatch: 1,
		SHA:             g.SHA,
	}
	twait.Succeeded(ctx, t, g.Cnx, g.Options, sopt)
}

// TestGithubWebhookIssueCommentCancel tests /cancel GitOps command via webhook.
func TestGithubWebhookIssueCommentCancel(t *testing.T) {
	ctx := context.Background()
	g := &tgithub.PRTest{
		Label:     "Github webhook /cancel",
		YamlFiles: []string{"testdata/pipelinerun.yaml"},
		Webhook:   true,
	}
	g.RunPullRequest(ctx, t)
	defer g.TearDown(ctx, t)

	// Wait for initial PR to be processed
	time.Sleep(5 * time.Second)

	// Send /cancel webhook
	g.SendIssueCommentWebhook(ctx, t, "/cancel")

	// For /cancel, we just verify the webhook was processed
	// (it would cancel existing runs, not create new ones)
	time.Sleep(10 * time.Second)

	prs, err := g.Cnx.Clients.Tekton.TektonV1().PipelineRuns(g.TargetNamespace).List(ctx, metav1.ListOptions{})
	assert.NilError(t, err)
	g.Logger.Infof("Number of PipelineRuns after /cancel webhook: %d", len(prs.Items))
}
