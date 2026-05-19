/**
 * @description  Reusable wrapper for invoking Salesforce Einstein Prompt Templates from Apex.
 *               Encapsulates the ConnectApi.EinsteinLLM invocation pattern.
 *
 * @author       Anup Chandran (Emirates Group IT)
 * @phase        Sales360 PoC - Phase 7
 * @since        May 2026
 *
 * @example
 *               Map<String, String> inputs = new Map<String, String>{
 *                   'userId' => 'USER_001',
 *                   'fiscalPeriod' => 'FY26Q1',
 *                   'agencyDataJson' => '[...]'
 *               };
 *               String jsonResponse = PromptTemplateInvoker.invoke(
 *                   'Portfolio_Summary_JSON_Template', inputs);
 */
public with sharing class PromptTemplateInvoker {

    /**
     * Invokes a Prompt Template with the provided input parameters and returns the LLM-generated text.
     *
     * @param templateApiName  The Prompt Template API name (e.g., 'Portfolio_Summary_JSON_Template')
     * @param inputParameters  Map of input parameter name to value (no 'Input:' prefix needed)
     * @return                 The LLM-generated text output (typically JSON)
     * @throws InvocationException on any error from the underlying ConnectApi call
     */
    public static String invoke(String templateApiName,
                                 Map<String, String> inputParameters) {
        if (String.isBlank(templateApiName)) {
            throw new InvocationException('templateApiName is required');
        }
        if (inputParameters == null || inputParameters.isEmpty()) {
            throw new InvocationException('inputParameters is required');
        }

        // Build input map with 'Input:' prefix (required by ConnectApi)
        Map<String, ConnectApi.WrappedValue> wrappedParams =
            new Map<String, ConnectApi.WrappedValue>();
        for (String key : inputParameters.keySet()) {
            ConnectApi.WrappedValue wv = new ConnectApi.WrappedValue();
            wv.value = inputParameters.get(key);
            wrappedParams.put('Input:' + key, wv);
        }

        // Build generations input
        ConnectApi.EinsteinPromptTemplateGenerationsInput genInput =
            new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        genInput.inputParams = wrappedParams;
        genInput.isPreview = false;
        genInput.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
        genInput.additionalConfig.applicationName = 'PromptBuilderPreview';

        // Invoke
        try {
            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation response =
                ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
                    templateApiName,
                    genInput
                );
            if (response == null || response.generations == null ||
                response.generations.isEmpty()) {
                throw new InvocationException('Empty response from LLM');
            }
            return response.generations[0].text;
        } catch (Exception e) {
            throw new InvocationException(
                'Failed to invoke ' + templateApiName + ': ' + e.getMessage());
        }
    }

    /**
     * Custom exception for Prompt Template invocation errors.
     */
    public class InvocationException extends Exception {}
}
