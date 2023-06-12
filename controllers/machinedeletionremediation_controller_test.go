package controllers

import (
	"context"
	"fmt"
	"time"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"

	v1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"

	"github.com/openshift/machine-api-operator/pkg/apis/machine/v1beta1"

	"github.com/medik8s/machine-deletion-remediation/api/v1alpha1"
)

const (
	defaultNamespace                                     = "default"
	dummyMachine                                         = "dummy-machine"
	workerNodeName, masterNodeName, noneExistingNodeName = "worker-node-x", "master-node-x", "phantom-node"
	workerNodeMachineName, masterNodeMachineName         = "worker-node-x-machine", "master-node-x-machine"
	mockDeleteFailMessage                                = "mock delete failure"
)

var _ = Describe("Machine Deletion Remediation CR", func() {
	var (
		underTest                            *v1alpha1.MachineDeletionRemediation
		workerNodeMachine, masterNodeMachine *v1beta1.Machine
		workerNode, masterNode               *v1.Node
		//phantomNode is never created by client
		phantomNode *v1.Node
	)

	Context("Defaults", func() {
		BeforeEach(func() {
			underTest = &v1alpha1.MachineDeletionRemediation{
				ObjectMeta: metav1.ObjectMeta{Name: "test", Namespace: defaultNamespace},
			}
			DeferCleanup(k8sClient.Delete, underTest)
			Expect(k8sClient.Create(context.Background(), underTest)).To(Succeed())
		})

		When("creating a resource", func() {
			It("CR is namespace scoped", func() {
				Expect(underTest.Namespace).To(Not(BeEmpty()))
			})

		})
	})

	Context("Reconciliation", func() {
		BeforeEach(func() {
			plogs.Clear()
			workerNodeMachine, masterNodeMachine = createWorkerMachine(workerNodeMachineName), createMachine(masterNodeMachineName)
			workerNode, masterNode, phantomNode = createNodeWithMachine(workerNodeName, workerNodeMachine), createNodeWithMachine(masterNodeName, masterNodeMachine), createNode(noneExistingNodeName)

			DeferCleanup(k8sClient.Delete, masterNode)
			DeferCleanup(k8sClient.Delete, workerNode)
			DeferCleanup(k8sClient.Delete, masterNodeMachine)
			DeferCleanup(deleteIgnoreNotFound(), workerNodeMachine)
			Expect(k8sClient.Create(context.Background(), masterNode)).To(Succeed())
			Expect(k8sClient.Create(context.Background(), workerNode)).To(Succeed())
			Expect(k8sClient.Create(context.Background(), masterNodeMachine)).To(Succeed())
			Expect(k8sClient.Create(context.Background(), workerNodeMachine)).To(Succeed())
		})

		JustBeforeEach(func() {
			DeferCleanup(k8sClient.Delete, underTest)
			Expect(k8sClient.Create(context.Background(), underTest)).To(Succeed())
		})

		Context("Sunny Flows", func() {
			When("remediation does not exist", func() {
				BeforeEach(func() {
					underTest = createRemediation(phantomNode)
				})

				It("No machine is deleted", func() {
					verifyMachineNotDeleted(workerNodeMachineName)
					verifyMachineNotDeleted(masterNodeMachineName)
				})
			})

			When("remediation associated machine has no owner ref", func() {
				BeforeEach(func() {
					underTest = createRemediation(masterNode)
				})

				It("No machine is deleted", func() {
					verifyMachineNotDeleted(workerNodeMachineName)
					verifyMachineNotDeleted(masterNodeMachineName)
				})
			})

			When("remediation associated machine has owner ref without controller", func() {
				BeforeEach(func() {
					workerNodeMachine.OwnerReferences[0].Controller = nil
					Expect(k8sClient.Update(context.Background(), workerNodeMachine)).ToNot(HaveOccurred())
					underTest = createRemediation(workerNode)
				})

				It("No machine is deleted", func() {
					verifyMachineNotDeleted(workerNodeMachineName)
					verifyMachineNotDeleted(masterNodeMachineName)
				})
			})

			When("remediation associated machine has owner ref with controller set to false", func() {
				BeforeEach(func() {
					controllerValue := false
					workerNodeMachine.OwnerReferences[0].Controller = &controllerValue
					Expect(k8sClient.Update(context.Background(), workerNodeMachine)).ToNot(HaveOccurred())
					underTest = createRemediation(workerNode)
				})

				It("No machine is deleted", func() {
					verifyMachineNotDeleted(workerNodeMachineName)
					verifyMachineNotDeleted(masterNodeMachineName)
				})
			})

			When("worker node remediation exist", func() {
				BeforeEach(func() {
					underTest = createRemediation(workerNode)
				})
				It("worker machine is deleted", func() {
					verifyMachineIsDeleted(workerNodeMachineName)
					verifyMachineNotDeleted(masterNodeMachineName)

					Expect(k8sClient.Get(context.Background(), client.ObjectKeyFromObject(underTest), underTest)).To(Succeed())
					Expect(underTest.GetAnnotations()).ToNot(BeNil())
				})
			})
		})

		Context("Rainy (Error) Flows", func() {
			When("remediation is not connected to a node", func() {
				BeforeEach(func() {
					underTest = createRemediation(phantomNode)
				})

				It("node not found error", func() {
					Eventually(func() bool {
						return plogs.Contains(noNodeFoundError)
					}, 30*time.Second, 1*time.Second).Should(BeTrue())
				})
			})

			When("node does not have annotations", func() {
				BeforeEach(func() {
					underTest = createRemediation(masterNode)
					masterNode.Annotations = nil
					Expect(k8sClient.Update(context.Background(), masterNode)).ToNot(HaveOccurred())
				})

				It("no annotations error", func() {
					Eventually(func() bool {
						return plogs.Contains(fmt.Sprintf(noAnnotationsError, underTest.Name))
					}, 30*time.Second, 1*time.Second).Should(BeTrue())
				})
			})

			When("node does not have machine annotation", func() {
				BeforeEach(func() {
					underTest = createRemediation(masterNode)
					masterNode.Annotations[machineAnnotationOpenshift] = ""
					Expect(k8sClient.Update(context.Background(), masterNode)).ToNot(HaveOccurred())
				})

				It("no machine annotation error", func() {
					Eventually(func() bool {
						return plogs.Contains(fmt.Sprintf(noMachineAnnotationError, underTest.Name))
					}, 30*time.Second, 1*time.Second).Should(BeTrue())
				})
			})

			When("node's machine annotation has invalid value", func() {
				BeforeEach(func() {
					underTest = createRemediation(masterNode)
					masterNode.Annotations[machineAnnotationOpenshift] = "Gibberish"
					Expect(k8sClient.Update(context.Background(), masterNode)).ToNot(HaveOccurred())
				})

				It("failed to extract Name/Namespace from machine annotation error", func() {
					Eventually(func() bool {
						return plogs.Contains(fmt.Sprintf(invalidValueMachineAnnotationError, underTest.Name))
					}, 30*time.Second, 1*time.Second).Should(BeTrue())
				})
			})

			When("node's machine annotation has incorrect value", func() {
				BeforeEach(func() {
					underTest = createRemediation(masterNode)
					masterNode.Annotations[machineAnnotationOpenshift] = "phantom-machine-namespace/phantom-machine-name"
					Expect(k8sClient.Update(context.Background(), masterNode)).ToNot(HaveOccurred())
				})

				It("failed to fetch machine error", func() {
					Eventually(func() bool {
						return plogs.Contains(noMachineFoundError)
					}, 30*time.Second, 1*time.Second).Should(BeTrue())
				})
			})

			When("Remediation has incorrect annotation", func() {
				BeforeEach(func() {
					underTest = createRemediationWithAnnotation(masterNode, "Gibberish")
				})

				It("fails to follow machine deletion", func() {
					Eventually(func() bool {
						return plogs.Contains("could not get Machine data from remediation")
					}, 30*time.Second, 1*time.Second).Should(BeTrue())
				})
			})

			When("machine associated to worker node fails deletion", func() {
				BeforeEach(func() {
					cclient.onDeleteError = fmt.Errorf(mockDeleteFailMessage)
					underTest = createRemediation(workerNode)
				})

				It("returns the same delete failure error", func() {
					Eventually(func() bool {
						return plogs.Contains(mockDeleteFailMessage)
					}, 30*time.Second, 1*time.Second).Should(BeTrue())
				})
			})
		})
	})
})

func createRemediation(node *v1.Node) *v1alpha1.MachineDeletionRemediation {
	mdr := &v1alpha1.MachineDeletionRemediation{}
	mdr.Name = node.Name
	mdr.Namespace = defaultNamespace
	return mdr
}

func createRemediationWithAnnotation(node *v1.Node, annotation string) *v1alpha1.MachineDeletionRemediation {
	mdr := createRemediation(node)
	annotations := make(map[string]string, 1)
	annotations[MachineNameNamespaceAnnotation] = fmt.Sprintf("%s", annotation)
	mdr.SetAnnotations(annotations)
	return mdr
}

func createNodeWithMachine(nodeName string, machine *v1beta1.Machine) *v1.Node {
	n := createNode(nodeName)
	n.Annotations[machineAnnotationOpenshift] = fmt.Sprintf("%s/%s", machine.GetNamespace(), machine.GetName())
	return n
}
func createNode(nodeName string) *v1.Node {
	n := &v1.Node{}
	n.Name = nodeName
	n.Annotations = map[string]string{}
	return n
}

func createDummyMachine() *v1beta1.Machine {
	return createMachine(dummyMachine)
}
func createMachine(machineName string) *v1beta1.Machine {
	machine := &v1beta1.Machine{}
	machine.SetNamespace(defaultNamespace)
	machine.SetName(machineName)
	return machine
}
func createWorkerMachine(machineName string) *v1beta1.Machine {
	controllerVal := true
	machine := createMachine(machineName)
	ref := metav1.OwnerReference{
		Name:       "machineSetX",
		Kind:       machineSetKind,
		UID:        "1234",
		APIVersion: v1beta1.SchemeGroupVersion.String(),
		Controller: &controllerVal,
	}
	machine.SetOwnerReferences([]metav1.OwnerReference{ref})
	return machine
}

func verifyMachineNotDeleted(machineName string) {
	Consistently(
		func() error {
			return k8sClient.Get(context.Background(), client.ObjectKey{Namespace: defaultNamespace, Name: machineName}, createDummyMachine())
		}).ShouldNot(HaveOccurred())
}

func verifyMachineIsDeleted(machineName string) {
	Eventually(func() bool {
		return errors.IsNotFound(k8sClient.Get(context.Background(), client.ObjectKey{Namespace: defaultNamespace, Name: machineName}, createDummyMachine()))
	}).Should(BeTrue())
}

func deleteIgnoreNotFound() func(ctx context.Context, obj client.Object) error {
	return func(ctx context.Context, obj client.Object) error {
		if err := k8sClient.Delete(ctx, obj); err != nil && !errors.IsNotFound(err) {
			return err
		}
		return nil
	}
}
