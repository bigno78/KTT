#include <string>

#include <Api/Output/BufferOutputDescriptor.h>
#include <Api/KttException.h>
#include <Kernel/Kernel.h>
#include <KernelArgument/KernelArgument.h>
#include <KernelRunner/KernelRunner.h>
#include <KernelRunner/ValidationData.h>
#include <Utility/ErrorHandling/Assert.h>
#include <Utility/Logger/Logger.h>

namespace ktt
{

ValidationData::ValidationData(KernelRunner& kernelRunner, const KernelArgument& argument) :
    m_KernelRunner(kernelRunner),
    m_Argument(argument),
    m_ValidationRange(static_cast<size_t>(argument.GetNumberOfElements())),
    m_Comparator(nullptr),
    m_ReferenceComputation(nullptr),
    m_ReferenceKernel(nullptr)
{
    const auto id = argument.GetId();

    if (argument.GetMemoryType() != ArgumentMemoryType::Vector)
    {
        throw KttException("Kernel argument with id " + std::to_string(id) + " is not a vector and cannot be validated");
    }

    if (argument.GetAccessType() == ArgumentAccessType::ReadOnly)
    {
        throw KttException("Kernel argument with id " + std::to_string(id) + " is read-only and cannot be validated");
    }
}

void ValidationData::SetValidationRange(const size_t range)
{
    m_ValidationRange = range;
}

void ValidationData::SetValueComparator(ValueComparator comparator)
{
    if (comparator == nullptr)
    {
        throw KttException("Value comparator must be a valid function");
    }

    m_Comparator = comparator;
}

void ValidationData::SetReferenceComputation(ReferenceComputation computation)
{
    m_ReferenceComputation = computation;
}

void ValidationData::SetReferenceKernel(const Kernel& kernel, const KernelConfiguration& configuration)
{
    m_ReferenceKernel = &kernel;
    m_ReferenceConfiguration = configuration;
}

size_t ValidationData::GetValidationRange() const
{
    return m_ValidationRange;
}

ValueComparator ValidationData::GetValueComparator() const
{
    KttAssert(HasValueComparator(), "Value comparator should be retrieved only after prior check");
    return m_Comparator;
}

bool ValidationData::HasValueComparator() const
{
    return static_cast<bool>(m_Comparator);
}

bool ValidationData::HasReferenceComputation() const
{
    return static_cast<bool>(m_ReferenceComputation);
}

bool ValidationData::HasReferenceKernel() const
{
    return m_ReferenceKernel != nullptr;
}

KernelId ValidationData::GetReferenceKernelId() const
{
    KttAssert(HasReferenceKernel(), "Reference kernel id should be retrieved only after prior check");
    return m_ReferenceKernel->GetId();
}

void ValidationData::ComputeReferenceResults()
{
    if (HasReferenceComputation())
    {
        ComputeReferenceWithFunction();
    }

    if (HasReferenceKernel())
    {
        ComputeReferenceWithKernel();
    }
}

void ValidationData::ClearReferenceResults()
{
    m_ReferenceResult.clear();
    m_ReferenceKernelResult.clear();
}

bool ValidationData::HasReferenceResults() const
{
    return (HasReferenceComputation() && !m_ReferenceResult.empty())
        || (HasReferenceKernel() && !m_ReferenceKernelResult.empty());
}

void ValidationData::ComputeReferenceWithFunction()
{
    KttAssert(HasReferenceComputation(), "Reference can be computed only with valid reference computation");
    Logger::LogInfo("Computing reference computation result for argument with id " + std::to_string(m_Argument.GetId()));
    
    const size_t referenceSize = m_ValidationRange * m_Argument.GetElementSize();
    m_ReferenceResult.resize(referenceSize);
    m_ReferenceComputation(m_ReferenceResult.data());
}

void ValidationData::ComputeReferenceWithKernel()
{
    KttAssert(HasReferenceKernel(), "Reference can be computed only with valid reference kernel");
    Logger::LogInfo("Computing reference kernel result for argument with id " + std::to_string(m_Argument.GetId()));

    const bool profiling = m_KernelRunner.IsProfilingActive();
    m_KernelRunner.SetProfiling(false);

    const size_t referenceSize = m_ValidationRange * m_Argument.GetElementSize();
    m_ReferenceKernelResult.resize(referenceSize);
    BufferOutputDescriptor descriptor(m_Argument.GetId(), m_ReferenceKernelResult.data(), referenceSize);
    m_KernelRunner.RunKernel(*m_ReferenceKernel, m_ReferenceConfiguration, KernelRunMode::ResultValidation, {descriptor});

    m_KernelRunner.SetProfiling(profiling);
}

} // namespace ktt
