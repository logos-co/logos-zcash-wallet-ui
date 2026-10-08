#pragma once

#include <QElapsedTimer>
#include <QHash>
#include <QJsonObject>
#include <QObject>
#include <QString>
#include <QTimer>

#include "rep_zcash_wallet_ui_source.h"
#include "logos_ui_plugin_context.h"

// The Zcash wallet's C++ half: every zcash_wallet_backend call is made here; the QML renders.
// m_readPoll backs up the backend's events; m_jobPoll follows a wallet job, m_sendPoll a send.
class ZcashWalletUiBackend : public ZcashWalletUiSimpleSource,
                             public LogosUiPluginContext
{
public:
    void refresh() override;
    void clearAndRefresh() override;

    void setActiveNetwork(QString network) override;
    void openWallet(QString name, QString password) override;
    void createWallet(QString name, QString password) override;
    void restoreWallet(QString name, QString password, QString phrase, int birthdayHeight) override;
    void changePassword(QString oldPassword, QString newPassword) override;
    QString revealSeed(QString password) override;
    QString exportViewingKey(QString password) override;
    void closeWallet() override;

    void prepareSend(QString recipient, QString amountZec, QString memo, bool allowMixedPools) override;
    void shieldAddress(QString address) override;
    void approveSend(QString password) override;
    void cancelSend() override;
    void dismissSend() override;

    void newAddress() override;
    void refreshHistory() override;
    void showHistoryPage(int page) override;
    void applyPreset(QString name) override;
    void setProxy(QString proxy) override;

protected:
    void onContextReady() override;

private:
    void say(const QString &line);
    bool ok(const QString &reply, const QString &context);
    bool walletOpen() const;
    void loadStatus();
    void loadRegistry();
    void loadSync();
    void loadBalances();
    void loadReceive();
    void loadServers();
    void loadServerHealth();
    void clearWalletReads();
    void readHistory(bool quiet);
    void syncHistoryToHeight();
    void track(const QString &reply, const QString &kind, const QString &name);
    void pollJob();
    bool clearSettledSend();
    void startSend(const QString &reply);
    void adoptSend(const QString &id);
    void recoverSend();
    void pollSend();
    QString qrModulesJson(const QString &text) const;

    QTimer m_readPoll;
    QTimer m_jobPoll;
    QTimer m_sendPoll;
    QString m_pendingName;
    QString m_qrShieldedFor;
    QString m_qrTransparentFor;
    // Per network, as set_proxy answered it.
    QHash<QString, QString> m_proxySaved;
    // The scanned height the history on screen describes; -1 is "none read".
    qint64 m_historyHeight = -1;
    QElapsedTimer m_historyReadAge;
    bool m_historyHasPending = false;
};
