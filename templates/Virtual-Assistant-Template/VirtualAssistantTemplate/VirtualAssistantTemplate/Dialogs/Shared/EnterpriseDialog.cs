// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

using System;
using System.Threading;
using System.Threading.Tasks;
using VirtualAssistantTemplate.Dialogs.Cancel;
using VirtualAssistantTemplate.Dialogs.Main;
using Luis;
using Microsoft.Bot.Builder.Dialogs;
using Microsoft.Bot.Builder.Solutions.Dialogs;
using Microsoft.Bot.Builder;

namespace VirtualAssistantTemplate.Dialogs.Shared
{
    public class EnterpriseDialog : InterruptableDialog
    {
        protected const string LuisResultKey = "LuisResult";

        // Fields
        private readonly BotServices _services;
        private readonly CancelResponses _responder = new CancelResponses();

        public EnterpriseDialog(BotServices botServices, string dialogId, IBotTelemetryClient botTelemetryClient)
            : base(dialogId, botTelemetryClient)
        {
            _services = botServices;

            AddDialog(new CancelDialog());
        }

        protected override async Task<InterruptionAction> OnInterruptDialogAsync(DialogContext dc, CancellationToken cancellationToken)
        {
            // check luis intent
            var locale = dc.Context.Activity.Locale;
            _services.CognitiveModelSets[locale].LuisServices.TryGetValue("general", out var luisService);

            if (luisService == null)
            {
                throw new Exception("The specified LUIS Model could not be found in your Bot Services configuration.");
            }
            else
            {
                General luisResult;
                if (dc.Context.TurnState.ContainsKey(LuisResultKey))
                {
                    luisResult = dc.Context.TurnState.Get<General>(LuisResultKey);
                }
                else
                {
                    luisResult = await luisService.RecognizeAsync<General>(dc.Context, cancellationToken);

                    // Add the luis result (intent and entities) for further processing in the derived dialog
                    dc.Context.TurnState.Add(LuisResultKey, luisResult);
                }

                var intent = luisResult.TopIntent().intent;

                // Only triggers interruption if confidence level is high
                if (luisResult.TopIntent().score > 0.5)
                {
                    switch (intent)
                    {
                        case General.Intent.Cancel:
                            {
                                return await OnCancel(dc);
                            }

                        case General.Intent.Help:
                            {
                                return await OnHelp(dc);
                            }
                    }
                }
            }

            return InterruptionAction.NoAction;
        }

        protected virtual async Task<InterruptionAction> OnCancel(DialogContext dc)
        {
            if (dc.ActiveDialog.Id != nameof(CancelDialog))
            {
                // Don't start restart cancel dialog
                await dc.BeginDialogAsync(nameof(CancelDialog));

                // Signal that the dialog is waiting on user response
                return InterruptionAction.StartedDialog;
            }

            // Else, continue
            return InterruptionAction.NoAction;
        }

        protected virtual async Task<InterruptionAction> OnHelp(DialogContext dc)
        {
            var view = new MainResponses();
            await view.ReplyWith(dc.Context, MainResponses.ResponseIds.Help);

            // Signal the conversation was interrupted and should immediately continue
            return InterruptionAction.MessageSentToUser;
        }
    }
}
